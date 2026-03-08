from __future__ import annotations

import contextlib
import re
from dataclasses import asdict, dataclass
from typing import Any, Protocol, cast

from sync_backend.alignment.audio import PreparedAudioSegment
from sync_backend.config import Settings


class TranscriptionError(RuntimeError):
    pass


@dataclass(slots=True)
class TranscriptWord:
    text: str
    start_ms: int
    end_ms: int
    confidence: float


@dataclass(slots=True)
class TranscriptSegment:
    asset_id: str
    segment_index: int
    start_ms: int
    end_ms: int
    words: list[TranscriptWord]


class SegmentTranscriber(Protocol):
    def transcribe_segment(self, segment: PreparedAudioSegment) -> list[TranscriptWord]: ...


class StaticTranscriber:
    def __init__(self, transcript_text: str) -> None:
        self.transcript_text = transcript_text
        self.resolved_language: str | None = None

    def set_preferred_language(self, language: str | None) -> None:
        self.resolved_language = normalize_language_code(language)

    def transcribe_segment(self, segment: PreparedAudioSegment) -> list[TranscriptWord]:
        words = [word for word in self.transcript_text.split() if word.strip()]
        if not words:
            return []

        step_ms = max(1, segment.duration_ms // len(words))
        transcript_words: list[TranscriptWord] = []
        for index, word in enumerate(words):
            start_ms = segment.start_ms + (index * step_ms)
            end_ms = segment.end_ms if index == len(words) - 1 else start_ms + step_ms
            transcript_words.append(
                TranscriptWord(
                    text=word,
                    start_ms=start_ms,
                    end_ms=end_ms,
                    confidence=0.5,
                )
            )
        return transcript_words


class WhisperXTranscriber:
    def __init__(self, *, settings: Settings) -> None:
        self.model_name = settings.whisper_model_name
        self.detected_language: str | None = None
        self.alignment_language: str | None = None
        self.preferred_language: str | None = None
        self.resolved_language: str | None = None
        self.device = "cpu"
        self.compute_type = "int8"
        self.batch_size = 1
        self._loaded = False
        self._whisperx: Any | None = None
        self._model: Any | None = None
        self._align_model: Any | None = None
        self._metadata: Any | None = None

    def set_preferred_language(self, language: str | None) -> None:
        self.preferred_language = normalize_language_code(language)

    def _ensure_loaded(self) -> None:
        if self._loaded:
            return
        try:
            import whisperx  # type: ignore[import-untyped]
        except ImportError as exc:  # pragma: no cover
            raise TranscriptionError(
                "WhisperX is not installed. Install it or set TRANSCRIBER_PROVIDER=static."
            ) from exc

        torch_mod: Any | None = None
        with contextlib.suppress(ImportError):
            import torch as torch_mod

        if torch_mod is not None and torch_mod.cuda.is_available():
            self.device = "cuda"
            self.compute_type = "float16"
            self.batch_size = 4

        self._whisperx = whisperx
        self._model = whisperx.load_model(
            self.model_name,
            device=self.device,
            compute_type=self.compute_type,
        )
        self._loaded = True

    def transcribe_segment(self, segment: PreparedAudioSegment) -> list[TranscriptWord]:
        self._ensure_loaded()
        assert self._whisperx is not None
        assert self._model is not None

        audio = self._whisperx.load_audio(str(segment.absolute_path))
        result = self._model.transcribe(
            audio,
            batch_size=self.batch_size,
            language=self.preferred_language,
        )
        detected_language = normalize_language_code(result.get("language"))
        alignment_language = self.preferred_language or detected_language
        self.detected_language = detected_language
        self.resolved_language = alignment_language or detected_language or self.preferred_language

        aligned: dict[str, Any] | None = None
        if alignment_language is not None:
            aligned = self._align_result(
                result=result,
                audio=audio,
                alignment_language=alignment_language,
            )

        if aligned is None:
            return build_fallback_words(
                segment=segment,
                segments=result.get("segments", []),
            )

        words: list[TranscriptWord] = []
        for word in aligned.get("word_segments", []):
            if "word" not in word:
                continue
            start_ms = segment.start_ms + int(float(word.get("start", 0)) * 1000)
            end_ms = segment.start_ms + int(float(word.get("end", 0)) * 1000)
            words.append(
                TranscriptWord(
                    text=str(word["word"]),
                    start_ms=start_ms,
                    end_ms=end_ms,
                    confidence=float(word.get("score", 0.0)),
                )
            )
        if words:
            return words
        return build_fallback_words(
            segment=segment,
            segments=result.get("segments", []),
        )

    def _align_result(
        self,
        *,
        result: dict[str, Any],
        audio: Any,
        alignment_language: str,
    ) -> dict[str, Any] | None:
        assert self._whisperx is not None

        if self._align_model is None or self.alignment_language != alignment_language:
            try:
                self._align_model, self._metadata = self._whisperx.load_align_model(
                    language_code=alignment_language,
                    device=self.device,
                )
                self.alignment_language = alignment_language
            except Exception:
                self._align_model = None
                self._metadata = None
                self.alignment_language = None
                return None

        if self._align_model is None or self._metadata is None:
            return None

        try:
            return cast(
                dict[str, Any],
                self._whisperx.align(
                    result["segments"],
                    self._align_model,
                    self._metadata,
                    audio,
                    device=self.device,
                ),
            )
        except Exception:
            return None


def normalize_language_code(language: str | None) -> str | None:
    if language is None:
        return None

    normalized = language.strip().replace("_", "-").lower()
    if not normalized or normalized in {"auto", "und", "unknown", "none", "null"}:
        return None

    primary = normalized.split("-", maxsplit=1)[0]
    if not primary or not re.fullmatch(r"[a-z]{2,3}", primary):
        return None
    return primary


def build_fallback_words(
    *,
    segment: PreparedAudioSegment,
    segments: list[dict[str, Any]],
) -> list[TranscriptWord]:
    fallback_words: list[TranscriptWord] = []
    for raw_segment in segments:
        text = str(raw_segment.get("text", ""))
        words = [part for part in text.split() if part.strip()]
        if not words:
            continue

        raw_start_ms = int(float(raw_segment.get("start", 0.0)) * 1000)
        raw_end_ms = int(float(raw_segment.get("end", raw_start_ms / 1000)) * 1000)
        segment_start_ms = segment.start_ms + max(0, raw_start_ms)
        segment_end_ms = segment.start_ms + max(raw_start_ms + 1, raw_end_ms)
        window_ms = max(1, segment_end_ms - segment_start_ms)
        step_ms = max(1, window_ms // len(words))

        for index, word in enumerate(words):
            start_ms = segment_start_ms + (index * step_ms)
            end_ms = segment_end_ms if index == len(words) - 1 else min(
                segment_end_ms,
                start_ms + step_ms,
            )
            fallback_words.append(
                TranscriptWord(
                    text=word,
                    start_ms=start_ms,
                    end_ms=max(start_ms + 1, end_ms),
                    confidence=0.0,
                )
            )
    return fallback_words


def get_transcriber(settings: Settings) -> SegmentTranscriber:
    if settings.transcriber_provider == "static":
        return StaticTranscriber(settings.mock_transcript_text)
    if settings.transcriber_provider == "whisperx":
        return WhisperXTranscriber(settings=settings)
    raise TranscriptionError(f"Unsupported transcriber provider: {settings.transcriber_provider}")


def transcript_payload(
    *,
    project_id: str,
    job_id: str,
    language: str | None,
    segments: list[TranscriptSegment],
) -> dict[str, Any]:
    return {
        "version": "1.0",
        "project_id": project_id,
        "job_id": job_id,
        "language": language,
        "segments": [
            {
                "asset_id": segment.asset_id,
                "segment_index": segment.segment_index,
                "start_ms": segment.start_ms,
                "end_ms": segment.end_ms,
                "words": [asdict(word) for word in segment.words],
            }
            for segment in segments
        ],
    }
