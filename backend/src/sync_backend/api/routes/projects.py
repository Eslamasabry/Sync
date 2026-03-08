from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from sync_backend.api.dependencies import get_db_session
from sync_backend.api.errors import ApiError
from sync_backend.api.realtime import broker
from sync_backend.api.schemas import (
    AssetCreateRequest,
    AssetCreateResponse,
    AssetSummary,
    JobCreateRequest,
    JobCreateResponse,
    JobDetailResponse,
    JobProgress,
    JobQuality,
    JobSummary,
    MatchArtifactResponse,
    ProjectCreateRequest,
    ProjectCreateResponse,
    ProjectDetailResponse,
    ReaderModelResponse,
    SyncArtifactResponse,
    TranscriptArtifactResponse,
)
from sync_backend.config import get_settings
from sync_backend.models import (
    AlignmentJob,
    Asset,
    MatchArtifact,
    ReaderModelArtifact,
    SyncArtifact,
    TranscriptArtifact,
)
from sync_backend.services import (
    cancel_job,
    create_alignment_job,
    create_project,
    generate_reader_model_artifact,
    get_asset_or_404,
    get_job_or_404,
    get_latest_job,
    get_latest_sync_artifact,
    get_match_artifact_or_404,
    get_project_asset_or_404,
    get_project_or_404,
    get_reader_model_artifact_or_404,
    get_transcript_artifact_or_404,
    parse_uuid,
    register_asset,
    store_uploaded_asset,
)
from sync_backend.storage import get_object_store
from sync_backend.workers.pipeline import run_alignment_job_task

router = APIRouter(prefix="/projects", tags=["projects"])
DbSession = Annotated[Session, Depends(get_db_session)]


def _as_uuid(value: str | None) -> UUID | None:
    return UUID(value) if value is not None else None


def _asset_summary(asset: Asset) -> AssetSummary:
    return AssetSummary(
        asset_id=UUID(asset.id),
        kind=asset.kind,
        filename=asset.filename,
        content_type=asset.content_type,
        upload_mode=asset.upload_mode,
        status=asset.status,
        size_bytes=asset.size_bytes,
        created_at=asset.created_at,
    )


def _job_summary(job: AlignmentJob) -> JobSummary:
    return JobSummary(
        job_id=UUID(job.id),
        job_type=job.job_type,
        status=job.status,
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


def _job_detail(job: AlignmentJob) -> JobDetailResponse:
    return JobDetailResponse(
        job_id=UUID(job.id),
        status=job.status,
        progress=JobProgress(stage=job.progress_stage, percent=job.progress_percent),
        quality=JobQuality(
            match_confidence=job.match_confidence,
            mismatch_ranges=job.mismatch_ranges,
        ),
        book_asset_id=UUID(job.book_asset_id),
        audio_asset_ids=[UUID(asset_id) for asset_id in job.audio_asset_ids],
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


def _sync_response(project_id: str, artifact: SyncArtifact) -> SyncArtifactResponse:
    return SyncArtifactResponse(
        project_id=UUID(project_id),
        job_id=_as_uuid(artifact.job_id),
        version=artifact.version,
        status=artifact.status,
        download_url=artifact.download_url,
        inline_payload=artifact.inline_payload,
        created_at=artifact.created_at,
        updated_at=artifact.updated_at,
    )


def _reader_model_response(
    *,
    project_id: str,
    artifact: ReaderModelArtifact,
) -> ReaderModelResponse:
    object_store = get_object_store()
    return ReaderModelResponse(
        project_id=UUID(project_id),
        asset_id=UUID(artifact.asset_id),
        version=artifact.version,
        status=artifact.status,
        model=object_store.read_json(artifact.storage_path),
    )


def _transcript_response(
    *,
    project_id: str,
    artifact: TranscriptArtifact,
) -> TranscriptArtifactResponse:
    object_store = get_object_store()
    return TranscriptArtifactResponse(
        project_id=UUID(project_id),
        job_id=UUID(artifact.job_id),
        version=artifact.version,
        status=artifact.status,
        language=artifact.language,
        segment_count=artifact.segment_count,
        word_count=artifact.word_count,
        payload=object_store.read_json(artifact.storage_path),
    )


def _match_response(
    *,
    project_id: str,
    artifact: MatchArtifact,
) -> MatchArtifactResponse:
    object_store = get_object_store()
    return MatchArtifactResponse(
        project_id=UUID(project_id),
        job_id=UUID(artifact.job_id),
        version=artifact.version,
        status=artifact.status,
        match_count=artifact.match_count,
        gap_count=artifact.gap_count,
        average_confidence=artifact.average_confidence,
        payload=object_store.read_json(artifact.storage_path),
    )


@router.post("", status_code=status.HTTP_201_CREATED, response_model=ProjectCreateResponse)
async def create_project_route(
    payload: ProjectCreateRequest,
    session: DbSession,
) -> ProjectCreateResponse:
    project = create_project(session=session, title=payload.title, language=payload.language)
    return ProjectCreateResponse(
        project_id=UUID(project.id),
        status=project.status,
        created_at=project.created_at,
    )


@router.post(
    "/{project_id}/assets",
    status_code=status.HTTP_201_CREATED,
    response_model=AssetCreateResponse,
)
async def register_asset_route(
    project_id: str,
    payload: AssetCreateRequest,
    session: DbSession,
) -> AssetCreateResponse:
    asset = register_asset(
        session=session,
        project_id=project_id,
        kind=payload.kind,
        filename=payload.filename,
        content_type=payload.content_type,
    )
    return AssetCreateResponse(
        asset_id=UUID(asset.id),
        upload_mode=asset.upload_mode,
        status=asset.status,
    )


@router.post(
    "/{project_id}/assets/upload",
    status_code=status.HTTP_201_CREATED,
    response_model=AssetCreateResponse,
)
async def upload_asset_route(
    project_id: str,
    kind: Annotated[str, Form(pattern="^(epub|audio)$")],
    file: Annotated[UploadFile, File()],
    session: DbSession,
) -> AssetCreateResponse:
    object_store = get_object_store()
    payload = await file.read()
    asset = store_uploaded_asset(
        session=session,
        project_id=project_id,
        kind=kind,
        filename=file.filename or "upload.bin",
        content_type=file.content_type or "application/octet-stream",
        payload=payload,
        object_store=object_store,
    )
    if kind == "epub":
        generate_reader_model_artifact(
            session=session,
            project_id=project_id,
            asset=asset,
            object_store=object_store,
        )
    return AssetCreateResponse(
        asset_id=UUID(asset.id),
        upload_mode=asset.upload_mode,
        status=asset.status,
    )


@router.get("/{project_id}/assets/{asset_id}/content")
async def get_asset_content_route(
    project_id: str,
    asset_id: str,
    session: DbSession,
) -> FileResponse:
    asset = get_project_asset_or_404(
        session=session,
        project_id=project_id,
        asset_id=asset_id,
    )
    if asset.storage_path is None:
        missing_asset = get_asset_or_404(session=session, asset_id=asset_id)
        raise ApiError(
            code="asset_content_missing",
            message="Asset content is not available for download",
            details={"asset_id": missing_asset.id},
            status_code=status.HTTP_409_CONFLICT,
        )

    object_store = get_object_store()
    return FileResponse(
        path=object_store.absolute_path(asset.storage_path),
        media_type=asset.content_type,
        filename=asset.filename,
    )


@router.post(
    "/{project_id}/jobs",
    status_code=status.HTTP_201_CREATED,
    response_model=JobCreateResponse,
)
async def create_job_route(
    project_id: str,
    payload: JobCreateRequest,
    session: DbSession,
) -> JobCreateResponse:
    job = create_alignment_job(
        session=session,
        project_id=project_id,
        book_asset_id=parse_uuid(payload.book_asset_id),
        audio_asset_ids=[parse_uuid(asset_id) for asset_id in payload.audio_asset_ids],
    )
    await broker.broadcast(
        project_id=project_id,
        event_type="job.queued",
        job_id=job.id,
        payload={"stage": job.progress_stage, "percent": job.progress_percent},
    )
    settings = get_settings()
    if settings.app_env != "test":
        run_alignment_job_task.delay(project_id, job.id)
    return JobCreateResponse(job_id=UUID(job.id), status=job.status)


@router.get("/{project_id}", response_model=ProjectDetailResponse)
async def get_project_route(project_id: str, session: DbSession) -> ProjectDetailResponse:
    project = get_project_or_404(session=session, project_id=project_id)
    latest_job = get_latest_job(session=session, project_id=project_id)
    return ProjectDetailResponse(
        project_id=UUID(project.id),
        title=project.title,
        language=project.language,
        status=project.status,
        created_at=project.created_at,
        updated_at=project.updated_at,
        assets=[
            _asset_summary(asset)
            for asset in sorted(project.assets, key=lambda asset: asset.created_at)
        ],
        latest_job=_job_summary(latest_job) if latest_job else None,
    )


@router.get("/{project_id}/jobs/{job_id}", response_model=JobDetailResponse)
async def get_job_route(project_id: str, job_id: str, session: DbSession) -> JobDetailResponse:
    job = get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    return _job_detail(job)


@router.get(
    "/{project_id}/jobs/{job_id}/transcript",
    response_model=TranscriptArtifactResponse,
)
async def get_transcript_route(
    project_id: str,
    job_id: str,
    session: DbSession,
) -> TranscriptArtifactResponse:
    artifact = get_transcript_artifact_or_404(
        session=session,
        project_id=project_id,
        job_id=job_id,
    )
    return _transcript_response(project_id=project_id, artifact=artifact)


@router.get(
    "/{project_id}/jobs/{job_id}/matches",
    response_model=MatchArtifactResponse,
)
async def get_match_route(
    project_id: str,
    job_id: str,
    session: DbSession,
) -> MatchArtifactResponse:
    artifact = get_match_artifact_or_404(
        session=session,
        project_id=project_id,
        job_id=job_id,
    )
    return _match_response(project_id=project_id, artifact=artifact)


@router.get("/{project_id}/sync", response_model=SyncArtifactResponse)
async def get_sync_route(project_id: str, session: DbSession) -> SyncArtifactResponse:
    artifact = get_latest_sync_artifact(session=session, project_id=project_id)
    return _sync_response(project_id, artifact)


@router.get("/{project_id}/reader-model", response_model=ReaderModelResponse)
async def get_reader_model_route(project_id: str, session: DbSession) -> ReaderModelResponse:
    artifact = get_reader_model_artifact_or_404(session=session, project_id=project_id)
    return _reader_model_response(project_id=project_id, artifact=artifact)


@router.post("/{project_id}/jobs/{job_id}/cancel", response_model=JobCreateResponse)
async def cancel_job_route(project_id: str, job_id: str, session: DbSession) -> JobCreateResponse:
    job = cancel_job(session=session, project_id=project_id, job_id=job_id)
    await broker.broadcast(
        project_id=project_id,
        event_type="job.cancelled",
        job_id=job.id,
        payload={"stage": job.progress_stage, "percent": job.progress_percent},
    )
    return JobCreateResponse(job_id=UUID(job.id), status=job.status)
