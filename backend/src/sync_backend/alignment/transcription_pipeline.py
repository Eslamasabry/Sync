from __future__ import annotations

from uuid import uuid4

from sqlalchemy.orm import Session

from sync_backend.alignment.audio import AudioPreprocessor
from sync_backend.alignment.transcription import (
    SegmentTranscriber,
    TranscriptSegment,
    TranscriptWord,
    transcript_payload,
)
from sync_backend.api.realtime import publish_project_event_sync
from sync_backend.models import TranscriptArtifact
from sync_backend.services import (
    get_asset_or_404,
    get_job_or_404,
    get_project_or_404,
)
from sync_backend.storage import FileObjectStore


def transcribe_alignment_job(
    *,
    session: Session,
    project_id: str,
    job_id: str,
    object_store: FileObjectStore,
    preprocessor: AudioPreprocessor,
    transcriber: SegmentTranscriber,
) -> TranscriptArtifact:
    project = get_project_or_404(session=session, project_id=project_id)
    job = get_job_or_404(session=session, project_id=project_id, job_id=job_id)

    set_preferred_language = getattr(transcriber, "set_preferred_language", None)
    if callable(set_preferred_language):
        set_preferred_language(project.language)

    job.status = "running"
    job.progress_stage = "audio_preprocessing"
    job.progress_percent = 10
    session.add(job)
    session.commit()
    publish_project_event_sync(
        project_id=project_id,
        event_type="job.started",
        job_id=job_id,
        payload={"stage": job.progress_stage, "percent": job.progress_percent},
    )

    prepared_assets = []
    for audio_asset_id in job.audio_asset_ids:
        asset = get_asset_or_404(session=session, asset_id=audio_asset_id)
        segments = preprocessor.prepare_asset(project_id=project_id, asset=asset)
        prepared_assets.append((audio_asset_id, segments))

    total_segments = sum(len(segments) for _, segments in prepared_assets)
    processed_segments = 0
    transcript_segments: list[TranscriptSegment] = []
    timeline_offset_ms = 0
    for _audio_asset_id, segments in prepared_assets:
        asset_duration_ms = 0

        for segment in segments:
            words = [
                TranscriptWord(
                    text=word.text,
                    start_ms=timeline_offset_ms + word.start_ms,
                    end_ms=timeline_offset_ms + word.end_ms,
                    confidence=word.confidence,
                )
                for word in transcriber.transcribe_segment(segment)
            ]
            transcript_segments.append(
                TranscriptSegment(
                    asset_id=segment.asset_id,
                    segment_index=segment.segment_index,
                    start_ms=timeline_offset_ms + segment.start_ms,
                    end_ms=timeline_offset_ms + segment.end_ms,
                    words=words,
                )
            )
            asset_duration_ms = max(asset_duration_ms, segment.end_ms)
            processed_segments += 1
            job.progress_stage = "transcription"
            job.progress_percent = min(
                40,
                10 + int((processed_segments / max(1, total_segments)) * 30),
            )
            session.add(job)
            session.commit()
            publish_project_event_sync(
                project_id=project_id,
                event_type="job.progress",
                job_id=job_id,
                payload={"stage": job.progress_stage, "percent": job.progress_percent},
            )

        timeline_offset_ms += asset_duration_ms

    payload = transcript_payload(
        project_id=project_id,
        job_id=job_id,
        language=project.language,
        segments=transcript_segments,
    )
    artifact_id = str(uuid4())
    storage_path, size_bytes = object_store.write_json(
        f"projects/{project_id}/artifacts/transcript/{artifact_id}.json",
        payload,
    )
    word_count = sum(len(segment.words) for segment in transcript_segments)

    artifact = TranscriptArtifact(
        id=artifact_id,
        project_id=project_id,
        job_id=job_id,
        version="1.0",
        status="generated",
        language=project.language,
        segment_count=len(transcript_segments),
        word_count=word_count,
        storage_path=storage_path,
        size_bytes=size_bytes,
    )
    session.add(artifact)

    job.progress_stage = "transcription"
    job.progress_percent = 40
    session.add(job)
    session.commit()
    publish_project_event_sync(
        project_id=project_id,
        event_type="job.progress",
        job_id=job_id,
        payload={"stage": job.progress_stage, "percent": job.progress_percent},
    )
    session.refresh(artifact)
    return artifact
