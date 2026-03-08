import math
import struct
import sys
import wave
from io import BytesIO
from pathlib import Path
from types import SimpleNamespace
from typing import Protocol, cast

import pytest
from fastapi.testclient import TestClient

from sync_backend.alignment.audio import AudioPreprocessor, PreparedAudioSegment
from sync_backend.alignment.transcription import (
    SegmentTranscriber,
    TranscriptWord,
    WhisperXTranscriber,
)
from sync_backend.alignment.transcription_pipeline import transcribe_alignment_job
from sync_backend.config import Settings, get_settings
from sync_backend.db import get_session_factory
from sync_backend.storage import get_object_store


def make_test_wav_bytes(duration_seconds: float = 0.25, sample_rate: int = 16_000) -> bytes:
    frame_count = int(duration_seconds * sample_rate)
    buffer = BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        for frame_index in range(frame_count):
            sample = int(12000 * math.sin((2 * math.pi * 440 * frame_index) / sample_rate))
            wav_file.writeframes(struct.pack("<h", sample))
    return buffer.getvalue()


class RecordingTranscriber:
    def __init__(self) -> None:
        self.preferred_language: str | None = None

    def set_preferred_language(self, language: str | None) -> None:
        self.preferred_language = language

    def transcribe_segment(self, segment: object) -> list[TranscriptWord]:
        return [
            TranscriptWord(
                text="call",
                start_ms=0,
                end_ms=100,
                confidence=0.9,
            )
        ]


def test_transcription_pipeline_passes_project_language_to_transcriber(
    client: TestClient,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Language Project", "language": "en"},
    ).json()["project_id"]

    epub_asset_id = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "epub",
            "filename": "book.epub",
            "content_type": "application/epub+zip",
        },
    ).json()["asset_id"]

    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("clip.wav", make_test_wav_bytes(), "audio/wav")},
    ).json()["asset_id"]

    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    transcriber = RecordingTranscriber()
    settings = get_settings()
    session = get_session_factory()()
    try:
        transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=5_000,
            ),
            transcriber=transcriber,
        )
    finally:
        session.close()

    assert transcriber.preferred_language == "en"


class ResolvedLanguageTranscriber(RecordingTranscriber):
    def __init__(self) -> None:
        super().__init__()
        self.resolved_language = "fr"


class AssetWithId(Protocol):
    id: str


class FixedPreprocessor:
    def __init__(self, segments_by_asset: dict[str, list[PreparedAudioSegment]]) -> None:
        self.segments_by_asset = segments_by_asset

    def prepare_asset(
        self,
        *,
        project_id: str,
        asset: AssetWithId,
    ) -> list[PreparedAudioSegment]:
        return self.segments_by_asset[asset.id]


class FixedWordTranscriber:
    def __init__(self) -> None:
        self.resolved_language = "en"

    def set_preferred_language(self, language: str | None) -> None:
        return

    def transcribe_segment(self, segment: PreparedAudioSegment) -> list[TranscriptWord]:
        return [
            TranscriptWord(
                text=f"word-{segment.segment_index}",
                start_ms=segment.start_ms,
                end_ms=segment.start_ms + min(100, segment.duration_ms),
                confidence=0.9,
            )
        ]


def test_transcription_pipeline_persists_transcriber_resolved_language(
    client: TestClient,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Detected Language Project", "language": None},
    ).json()["project_id"]

    epub_asset_id = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "epub",
            "filename": "book.epub",
            "content_type": "application/epub+zip",
        },
    ).json()["asset_id"]

    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets/upload",
        data={"kind": "audio"},
        files={"file": ("clip.wav", make_test_wav_bytes(), "audio/wav")},
    ).json()["asset_id"]

    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    settings = get_settings()
    session = get_session_factory()()
    try:
        artifact = transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=AudioPreprocessor(
                object_store=get_object_store(),
                ffmpeg_bin=settings.ffmpeg_bin,
                ffprobe_bin=settings.ffprobe_bin,
                chunk_duration_ms=5_000,
            ),
            transcriber=ResolvedLanguageTranscriber(),
        )
    finally:
        session.close()

    assert artifact.language == "fr"

    transcript_response = client.get(f"/v1/projects/{project_id}/jobs/{job_id}/transcript")
    assert transcript_response.status_code == 200
    assert transcript_response.json()["payload"]["language"] == "fr"


def test_transcription_pipeline_progress_uses_audio_duration_weighting(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    project_id = client.post(
        "/v1/projects",
        json={"title": "Progress Project", "language": "en"},
    ).json()["project_id"]

    epub_asset_id = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "epub",
            "filename": "book.epub",
            "content_type": "application/epub+zip",
        },
    ).json()["asset_id"]

    audio_asset_id = client.post(
        f"/v1/projects/{project_id}/assets",
        json={
            "kind": "audio",
            "filename": "clip.wav",
            "content_type": "audio/wav",
        },
    ).json()["asset_id"]

    job_id = client.post(
        f"/v1/projects/{project_id}/jobs",
        json={
            "job_type": "alignment",
            "book_asset_id": epub_asset_id,
            "audio_asset_ids": [audio_asset_id],
        },
    ).json()["job_id"]

    published_events: list[dict[str, object]] = []

    def record_event(
        *,
        project_id: str,
        event_type: str,
        job_id: str,
        payload: dict[str, object],
    ) -> None:
        published_events.append(
            {
                "project_id": project_id,
                "event_type": event_type,
                "job_id": job_id,
                "payload": payload,
            }
        )

    monkeypatch.setattr(
        "sync_backend.alignment.transcription_pipeline.publish_project_event_sync",
        record_event,
    )

    segments = {
        audio_asset_id: [
            PreparedAudioSegment(
                asset_id=audio_asset_id,
                segment_index=0,
                storage_path="projects/test/segment-0.wav",
                start_ms=0,
                end_ms=1000,
                duration_ms=1000,
                absolute_path=tmp_path / "segment-0.wav",
            ),
            PreparedAudioSegment(
                asset_id=audio_asset_id,
                segment_index=1,
                storage_path="projects/test/segment-1.wav",
                start_ms=1000,
                end_ms=5000,
                duration_ms=4000,
                absolute_path=tmp_path / "segment-1.wav",
            ),
        ]
    }

    session = get_session_factory()()
    try:
        transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
            preprocessor=cast(AudioPreprocessor, FixedPreprocessor(segments)),
            transcriber=cast(SegmentTranscriber, FixedWordTranscriber()),
        )
    finally:
        session.close()

    progress_events = [
        event
        for event in published_events
        if event["event_type"] in {"job.started", "job.progress"}
    ]
    assert progress_events[0]["payload"] == {"stage": "audio_preprocessing", "percent": 0}
    transcription_events = [
        event["payload"]
        for event in progress_events
        if isinstance(event["payload"], dict) and event["payload"].get("stage") == "transcription"
    ]
    assert transcription_events[0]["percent"] == 16
    assert transcription_events[1]["percent"] == 40


def test_whisperx_transcriber_normalizes_language_and_falls_back_without_alignment(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    class FakeModel:
        def transcribe(
            self,
            audio: object,
            *,
            batch_size: int,
            language: str | None,
        ) -> dict[str, object]:
            assert audio == "audio-buffer"
            assert batch_size == 1
            assert language == "en"
            return {
                "language": "en-US",
                "segments": [
                    {"text": "Hello world", "start": 0.0, "end": 1.0},
                ],
            }

    fake_whisperx = SimpleNamespace(
        load_model=lambda model_name, device, compute_type: FakeModel(),
        load_audio=lambda path: "audio-buffer",
        load_align_model=lambda language_code, device: (_ for _ in ()).throw(
            RuntimeError("no align")
        ),
        align=lambda *args, **kwargs: {"word_segments": []},
    )
    fake_torch = SimpleNamespace(cuda=SimpleNamespace(is_available=lambda: False))

    monkeypatch.setitem(sys.modules, "whisperx", fake_whisperx)
    monkeypatch.setitem(sys.modules, "torch", fake_torch)

    segment_path = tmp_path / "segment.wav"
    segment_path.write_bytes(b"RIFF")
    transcriber = WhisperXTranscriber(settings=Settings())
    transcriber.set_preferred_language("en-US")

    words = transcriber.transcribe_segment(
        PreparedAudioSegment(
            asset_id="asset-1",
            segment_index=0,
            storage_path="projects/test/segment.wav",
            start_ms=2000,
            end_ms=3000,
            duration_ms=1000,
            absolute_path=segment_path,
        )
    )

    assert transcriber.preferred_language == "en"
    assert transcriber.detected_language == "en"
    assert transcriber.resolved_language == "en"
    assert [word.text for word in words] == ["Hello", "world"]
    assert words[0].start_ms == 2000
    assert words[0].end_ms == 2500
    assert words[1].start_ms == 2500
    assert words[1].end_ms == 3000
