from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Protocol

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
        self.language = None
        self.device = "cpu"
        self.compute_type = "int8"
        self._loaded = False
        self._whisperx: Any | None = None
        self._model: Any | None = None
        self._align_model: Any | None = None
        self._metadata: Any | None = None

    def _ensure_loaded(self) -> None:
        if self._loaded:
            return
        try:
            import whisperx  # type: ignore[import-not-found]
        except ImportError as exc:  # pragma: no cover
            raise TranscriptionError(
                "WhisperX is not installed. Install it or set TRANSCRIBER_PROVIDER=static."
            ) from exc

        try:
            import torch  # type: ignore[import-not-found]
        except ImportError:
            torch = None

        if torch is not None and torch.cuda.is_available():
            self.device = "cuda"
            self.compute_type = "float16"

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
        result = self._model.transcribe(audio, batch_size=1)
        language = result.get("language", "en")

        if self._align_model is None or self.language != language:
            self.language = language
            self._align_model, self._metadata = self._whisperx.load_align_model(
                language_code=language,
                device=self.device,
            )

        aligned = self._whisperx.align(
            result["segments"],
            self._align_model,
            self._metadata,
            audio,
            device=self.device,
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
        return words


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
