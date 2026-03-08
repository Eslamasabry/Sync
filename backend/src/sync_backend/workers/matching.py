from sqlalchemy.orm import Session

from sync_backend.alignment.matching_pipeline import build_match_artifact
from sync_backend.db import get_session_factory
from sync_backend.storage import get_object_store
from sync_backend.workers.celery_app import celery_app


@celery_app.task(name="sync_backend.build_match_artifact")
def build_match_artifact_task(project_id: str, job_id: str) -> None:
    session_factory = get_session_factory()
    session: Session = session_factory()
    try:
        build_match_artifact(
            session=session,
            project_id=project_id,
            job_id=job_id,
            object_store=get_object_store(),
        )
    finally:
        session.close()
