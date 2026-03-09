from __future__ import annotations

from sqlalchemy.orm import Session

from sync_backend.alignment.audio import AudioPreprocessor
from sync_backend.alignment.matching_pipeline import build_match_artifact
from sync_backend.alignment.sync_export import build_sync_artifact
from sync_backend.alignment.transcription import SegmentTranscriber
from sync_backend.alignment.transcription_pipeline import transcribe_alignment_job
from sync_backend.api.realtime import publish_project_event_sync
from sync_backend.services import get_job_or_404
from sync_backend.storage import ObjectStore


def run_alignment_job(
    *,
    session: Session,
    project_id: str,
    job_id: str,
    object_store: ObjectStore,
    preprocessor: AudioPreprocessor,
    transcriber: SegmentTranscriber,
) -> None:
    try:
        transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=object_store,
            preprocessor=preprocessor,
            transcriber=transcriber,
        )
        build_match_artifact(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=object_store,
        )
        build_sync_artifact(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=object_store,
        )
    except Exception:
        session.rollback()
        job = get_job_or_404(session=session, project_id=project_id, job_id=job_id)
        job.status = "failed"
        job.progress_stage = "failed"
        session.add(job)
        session.commit()
        publish_project_event_sync(
            project_id=project_id,
            event_type="job.failed",
            job_id=job_id,
            payload={"stage": job.progress_stage, "percent": job.progress_percent},
        )
        raise

    job = get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    job.status = "completed"
    job.progress_stage = "completed"
    job.progress_percent = 100
    session.add(job)
    session.commit()
    publish_project_event_sync(
        project_id=project_id,
        event_type="job.completed",
        job_id=job_id,
        payload={"stage": job.progress_stage, "percent": job.progress_percent},
    )
