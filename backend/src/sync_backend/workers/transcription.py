from sqlalchemy.orm import Session

from sync_backend.alignment.audio import AudioPreprocessor
from sync_backend.alignment.transcription import get_transcriber
from sync_backend.alignment.transcription_pipeline import transcribe_alignment_job
from sync_backend.config import get_settings
from sync_backend.db import get_session_factory
from sync_backend.storage import get_object_store
from sync_backend.workers.celery_app import celery_app


@celery_app.task(name="sync_backend.transcribe_alignment_job")
def transcribe_alignment_job_task(project_id: str, job_id: str) -> None:
    settings = get_settings()
    object_store = get_object_store()
    preprocessor = AudioPreprocessor(
        object_store=object_store,
        ffmpeg_bin=settings.ffmpeg_bin,
        ffprobe_bin=settings.ffprobe_bin,
        chunk_duration_ms=settings.audio_chunk_duration_ms,
    )
    transcriber = get_transcriber(settings)

    session_factory = get_session_factory()
    session: Session = session_factory()
    try:
        transcribe_alignment_job(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=object_store,
            preprocessor=preprocessor,
            transcriber=transcriber,
        )
    finally:
        session.close()
