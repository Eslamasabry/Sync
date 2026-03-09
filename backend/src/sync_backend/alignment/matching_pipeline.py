from __future__ import annotations

from uuid import uuid4

from sqlalchemy.orm import Session

from sync_backend.alignment.matching import match_transcript_to_reader_model
from sync_backend.api.realtime import publish_project_event_sync
from sync_backend.models import MatchArtifact
from sync_backend.services import (
    get_job_or_404,
    get_reader_model_artifact_or_404,
    get_transcript_artifact_or_404,
)
from sync_backend.storage import ObjectStore


def build_match_artifact(
    *,
    session: Session,
    project_id: str,
    job_id: str,
    object_store: ObjectStore,
) -> MatchArtifact:
    job = get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    reader_model_artifact = get_reader_model_artifact_or_404(session=session, project_id=project_id)
    transcript_artifact = get_transcript_artifact_or_404(
        session=session,
        project_id=project_id,
        job_id=job_id,
    )

    reader_model = object_store.read_json(reader_model_artifact.storage_path)
    transcript_payload = object_store.read_json(transcript_artifact.storage_path)
    match_payload = match_transcript_to_reader_model(
        transcript_payload=transcript_payload,
        reader_model=reader_model,
    )

    artifact_id = str(uuid4())
    storage_path, size_bytes = object_store.write_json(
        f"projects/{project_id}/artifacts/matches/{artifact_id}.json",
        match_payload,
    )

    artifact = MatchArtifact(
        id=artifact_id,
        project_id=project_id,
        job_id=job_id,
        version="1.0",
        status="generated",
        match_count=match_payload["match_count"],
        gap_count=match_payload["gap_count"],
        average_confidence=match_payload["average_confidence"],
        storage_path=storage_path,
        size_bytes=size_bytes,
    )
    session.add(artifact)

    job.progress_stage = "matching"
    job.progress_percent = 60
    job.match_confidence = match_payload["average_confidence"]
    job.mismatch_ranges = match_payload["gaps"]
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
