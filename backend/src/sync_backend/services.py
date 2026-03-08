from __future__ import annotations

from http import HTTPStatus
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from sync_backend.api.errors import ApiError, not_found
from sync_backend.models import AlignmentJob, Asset, Project, SyncArtifact


def create_project(*, session: Session, title: str, language: str | None) -> Project:
    project = Project(
        id=str(uuid4()),
        title=title,
        language=language,
        status="created",
    )
    session.add(project)
    session.commit()
    session.refresh(project)
    return project


def get_project_or_404(*, session: Session, project_id: str) -> Project:
    project = session.get(Project, project_id)
    if project is None:
        raise not_found("project_not_found", "Project was not found", {"project_id": project_id})
    return project


def register_asset(
    *,
    session: Session,
    project_id: str,
    kind: str,
    filename: str,
    content_type: str,
) -> Asset:
    get_project_or_404(session=session, project_id=project_id)

    asset = Asset(
        id=str(uuid4()),
        project_id=project_id,
        kind=kind,
        filename=filename,
        content_type=content_type,
        upload_mode="multipart",
        status="uploading",
    )
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset


def get_asset_or_404(*, session: Session, asset_id: str) -> Asset:
    asset = session.get(Asset, asset_id)
    if asset is None:
        raise not_found("asset_not_found", "Asset was not found", {"asset_id": asset_id})
    return asset


def create_alignment_job(
    *,
    session: Session,
    project_id: str,
    book_asset_id: str,
    audio_asset_ids: list[str],
) -> AlignmentJob:
    get_project_or_404(session=session, project_id=project_id)
    book_asset = get_asset_or_404(session=session, asset_id=book_asset_id)
    audio_assets = [
        get_asset_or_404(session=session, asset_id=asset_id)
        for asset_id in audio_asset_ids
    ]

    if book_asset.project_id != project_id or book_asset.kind != "epub":
        raise ApiError(
            code="asset_missing",
            message="An EPUB asset is required before creating an alignment job",
            status_code=HTTPStatus.BAD_REQUEST,
            details={"book_asset_id": book_asset_id},
        )

    for audio_asset in audio_assets:
        if audio_asset.project_id != project_id or audio_asset.kind != "audio":
            raise ApiError(
                code="asset_missing",
                message="At least one audio asset is invalid for this project",
                status_code=HTTPStatus.BAD_REQUEST,
                details={"audio_asset_id": audio_asset.id},
            )

    job = AlignmentJob(
        id=str(uuid4()),
        project_id=project_id,
        job_type="alignment",
        status="queued",
        book_asset_id=book_asset_id,
        audio_asset_ids=audio_asset_ids,
        progress_stage="queued",
        progress_percent=0,
        mismatch_ranges=[],
    )
    session.add(job)
    session.commit()
    session.refresh(job)
    return job


def get_job_or_404(*, session: Session, project_id: str, job_id: str) -> AlignmentJob:
    job = session.get(AlignmentJob, job_id)
    if job is None or job.project_id != project_id:
        raise not_found(
            "job_not_found",
            "Alignment job was not found",
            {"project_id": project_id, "job_id": job_id},
        )
    return job


def cancel_job(*, session: Session, project_id: str, job_id: str) -> AlignmentJob:
    job = get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    if job.status not in {"queued", "running"}:
        raise ApiError(
            code="job_not_cancellable",
            message="Only queued or running jobs can be cancelled",
            status_code=HTTPStatus.CONFLICT,
            details={"job_id": job_id, "status": job.status},
        )

    job.status = "cancelled"
    job.progress_stage = "cancelled"
    session.add(job)
    session.commit()
    session.refresh(job)
    return job


def get_latest_job(*, session: Session, project_id: str) -> AlignmentJob | None:
    return session.scalar(
        select(AlignmentJob)
        .where(AlignmentJob.project_id == project_id)
        .order_by(AlignmentJob.created_at.desc())
        .limit(1)
    )


def get_latest_sync_artifact(*, session: Session, project_id: str) -> SyncArtifact:
    artifact = session.scalar(
        select(SyncArtifact)
        .where(SyncArtifact.project_id == project_id)
        .order_by(SyncArtifact.created_at.desc())
        .limit(1)
    )
    if artifact is None:
        raise not_found("sync_not_found", "Sync artifact was not found", {"project_id": project_id})
    return artifact


def parse_uuid(value: UUID) -> str:
    return str(value)
