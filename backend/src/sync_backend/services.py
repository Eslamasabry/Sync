from __future__ import annotations

import hashlib
from http import HTTPStatus
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from sync_backend.alignment.epub import build_reader_model
from sync_backend.api.errors import ApiError, not_found
from sync_backend.models import (
    AlignmentJob,
    Asset,
    MatchArtifact,
    Project,
    ReaderModelArtifact,
    SyncArtifact,
    TranscriptArtifact,
)
from sync_backend.storage import ObjectStore


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


def store_uploaded_asset(
    *,
    session: Session,
    project_id: str,
    kind: str,
    filename: str,
    content_type: str,
    payload: bytes,
    object_store: ObjectStore,
) -> Asset:
    get_project_or_404(session=session, project_id=project_id)
    asset_id = str(uuid4())
    checksum = hashlib.sha256(payload).hexdigest()
    storage_path, size_bytes = object_store.write_bytes(
        f"projects/{project_id}/assets/{asset_id}/{filename}",
        payload,
    )

    asset = Asset(
        id=asset_id,
        project_id=project_id,
        kind=kind,
        filename=filename,
        content_type=content_type,
        upload_mode="multipart",
        status="uploaded",
        storage_path=storage_path,
        size_bytes=size_bytes,
        checksum_sha256=checksum,
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


def get_project_asset_or_404(*, session: Session, project_id: str, asset_id: str) -> Asset:
    asset = get_asset_or_404(session=session, asset_id=asset_id)
    if asset.project_id != project_id:
        raise not_found(
            "asset_not_found",
            "Asset was not found for this project",
            {"project_id": project_id, "asset_id": asset_id},
        )
    return asset


def get_reader_model_artifact_or_404(*, session: Session, project_id: str) -> ReaderModelArtifact:
    artifact = session.scalar(
        select(ReaderModelArtifact)
        .where(ReaderModelArtifact.project_id == project_id)
        .order_by(ReaderModelArtifact.created_at.desc())
        .limit(1)
    )
    if artifact is None:
        raise not_found(
            "reader_model_not_found",
            "Reader model artifact was not found",
            {"project_id": project_id},
        )
    return artifact


def generate_reader_model_artifact(
    *,
    session: Session,
    project_id: str,
    asset: Asset,
    object_store: ObjectStore,
) -> ReaderModelArtifact:
    if asset.kind != "epub" or asset.storage_path is None:
        raise ApiError(
            code="invalid_asset_type",
            message="Reader models can only be generated from uploaded EPUB assets",
            status_code=HTTPStatus.BAD_REQUEST,
            details={"asset_id": asset.id, "kind": asset.kind},
        )

    project = get_project_or_404(session=session, project_id=project_id)
    with object_store.materialize_file(asset.storage_path) as epub_path:
        reader_model = build_reader_model(
            epub_path,
            book_id=project_id,
            language=project.language,
        )
    artifact_id = str(uuid4())
    storage_path, size_bytes = object_store.write_json(
        f"projects/{project_id}/artifacts/reader-model/{artifact_id}.json",
        reader_model,
    )

    artifact = ReaderModelArtifact(
        id=artifact_id,
        project_id=project_id,
        asset_id=asset.id,
        version="1.0",
        status="generated",
        storage_path=storage_path,
        size_bytes=size_bytes,
    )
    session.add(artifact)
    session.commit()
    session.refresh(artifact)
    return artifact


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


def get_transcript_artifact_or_404(
    *,
    session: Session,
    project_id: str,
    job_id: str,
) -> TranscriptArtifact:
    artifact = session.scalar(
        select(TranscriptArtifact)
        .where(TranscriptArtifact.project_id == project_id)
        .where(TranscriptArtifact.job_id == job_id)
        .order_by(TranscriptArtifact.created_at.desc())
        .limit(1)
    )
    if artifact is None:
        raise not_found(
            "transcript_not_found",
            "Transcript artifact was not found",
            {"project_id": project_id, "job_id": job_id},
        )
    return artifact


def get_match_artifact_or_404(
    *,
    session: Session,
    project_id: str,
    job_id: str,
) -> MatchArtifact:
    artifact = session.scalar(
        select(MatchArtifact)
        .where(MatchArtifact.project_id == project_id)
        .where(MatchArtifact.job_id == job_id)
        .order_by(MatchArtifact.created_at.desc())
        .limit(1)
    )
    if artifact is None:
        raise not_found(
            "match_not_found",
            "Match artifact was not found",
            {"project_id": project_id, "job_id": job_id},
        )
    return artifact


def parse_uuid(value: UUID) -> str:
    return str(value)
