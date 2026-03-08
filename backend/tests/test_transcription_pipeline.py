import math
import struct
import wave
from io import BytesIO

from fastapi.testclient import TestClient

from sync_backend.alignment.audio import AudioPreprocessor
from sync_backend.alignment.transcription import TranscriptWord
from sync_backend.alignment.transcription_pipeline import transcribe_alignment_job
from sync_backend.config import get_settings
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
