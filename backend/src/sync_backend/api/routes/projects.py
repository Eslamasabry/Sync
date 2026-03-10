from __future__ import annotations

import os
from http import HTTPStatus
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, Request, UploadFile, status
from fastapi.responses import StreamingResponse
from sqlalchemy import select
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
    JobHistoryEntryResponse,
    JobProgress,
    JobQuality,
    JobSummary,
    MatchArtifactResponse,
    ProjectCreateRequest,
    ProjectCreateResponse,
    ProjectDetailResponse,
    ProjectJobHistoryResponse,
    ProjectListItemResponse,
    ProjectListResponse,
    ReaderModelResponse,
    SyncArtifactResponse,
    TranscriptArtifactResponse,
)
from sync_backend.config import get_settings
from sync_backend.models import (
    AlignmentJob,
    Asset,
    MatchArtifact,
    Project,
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
    mark_job_enqueue_failed,
    parse_uuid,
    register_asset,
    store_uploaded_asset,
)
from sync_backend.storage import get_object_store
from sync_backend.workers.pipeline import run_alignment_job_inline, run_alignment_job_task

router = APIRouter(prefix="/projects", tags=["projects"])
DbSession = Annotated[Session, Depends(get_db_session)]
UPLOAD_SIZE_LIMIT_ENV = "SYNC_UPLOAD_MAX_BYTES"


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
        checksum_sha256=asset.checksum_sha256,
        duration_ms=asset.duration_ms,
        download_url=None,
        created_at=asset.created_at,
    )


def _job_summary(job: AlignmentJob) -> JobSummary:
    return JobSummary(
        job_id=UUID(job.id),
        job_type=job.job_type,
        status=job.status,
        attempt_number=job.attempt_number,
        retry_of_job_id=_as_uuid(job.retry_of_job_id),
        terminal_reason=job.terminal_reason,
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


def _project_list_item(
    project: Project,
    latest_job: AlignmentJob | None,
) -> ProjectListItemResponse:
    assets = list(project.assets)
    return ProjectListItemResponse(
        project_id=UUID(project.id),
        title=project.title,
        language=project.language,
        status=project.status,
        updated_at=project.updated_at,
        asset_count=len(assets),
        audio_asset_count=sum(1 for asset in assets if asset.kind == "audio"),
        latest_job=_job_summary(latest_job) if latest_job else None,
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
        request_fingerprint=job.request_fingerprint,
        attempt_number=job.attempt_number,
        retry_of_job_id=_as_uuid(job.retry_of_job_id),
        terminal_reason=job.terminal_reason,
        book_asset_id=UUID(job.book_asset_id),
        audio_asset_ids=[UUID(asset_id) for asset_id in job.audio_asset_ids],
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


def _job_history_entry(job: AlignmentJob) -> JobHistoryEntryResponse:
    return JobHistoryEntryResponse(
        job_id=UUID(job.id),
        job_type=job.job_type,
        status=job.status,
        progress=JobProgress(stage=job.progress_stage, percent=job.progress_percent),
        request_fingerprint=job.request_fingerprint,
        attempt_number=job.attempt_number,
        retry_of_job_id=_as_uuid(job.retry_of_job_id),
        terminal_reason=job.terminal_reason,
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


def _validate_upload_metadata(*, filename: str, content_type: str, payload: bytes) -> None:
    if not payload:
        raise ApiError(
            code="asset_empty_upload",
            message="Uploaded asset content must not be empty",
            status_code=status.HTTP_400_BAD_REQUEST,
            details={"filename": filename},
        )
    if len(filename) > 255:
        raise ApiError(
            code="asset_filename_invalid",
            message="Uploaded asset filename exceeds the 255 character limit",
            status_code=status.HTTP_400_BAD_REQUEST,
            details={"filename_length": len(filename)},
        )
    if len(content_type) > 255:
        raise ApiError(
            code="asset_content_type_invalid",
            message="Uploaded asset content type exceeds the 255 character limit",
            status_code=status.HTTP_400_BAD_REQUEST,
            details={"content_type_length": len(content_type)},
        )


def _upload_size_limit_bytes() -> int | None:
    raw_value = os.getenv(UPLOAD_SIZE_LIMIT_ENV, "").strip()
    if not raw_value:
        return None

    try:
        value = int(raw_value)
    except ValueError:
        return None

    return value if value > 0 else None


def _raise_upload_too_large(
    *,
    filename: str,
    max_size_bytes: int,
    request_content_length_bytes: int | None = None,
    size_bytes: int | None = None,
) -> None:
    details: dict[str, int | str] = {
        "filename": filename,
        "max_size_bytes": max_size_bytes,
    }
    if request_content_length_bytes is not None:
        details["request_content_length_bytes"] = request_content_length_bytes
    if size_bytes is not None:
        details["size_bytes"] = size_bytes

    raise ApiError(
        code="asset_too_large",
        message="Uploaded asset exceeds the configured size limit",
        status_code=HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
        details=details,
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


def _download_url(
    request: Request,
    route_name: str,
    *,
    project_id: str,
    job_id: str | None = None,
) -> str:
    route_params: dict[str, str] = {"project_id": project_id}
    if job_id is not None:
        route_params["job_id"] = job_id
    return str(request.url_for(route_name, **route_params))


def _artifact_storage_missing_error(*, storage_path: str | None, filename: str) -> ApiError:
    return ApiError(
        code="artifact_content_missing",
        message="Artifact content is not available for download",
        status_code=status.HTTP_409_CONFLICT,
        details={"filename": filename, "storage_path": storage_path},
    )


def _content_response(
    *,
    storage_path: str | None,
    media_type: str,
    filename: str,
    size_bytes: int | None = None,
    checksum_sha256: str | None = None,
    byte_range: tuple[int, int] | None = None,
) -> StreamingResponse:
    if storage_path is None:
        raise _artifact_storage_missing_error(storage_path=storage_path, filename=filename)
    object_store = get_object_store()
    if not object_store.exists(storage_path):
        raise _artifact_storage_missing_error(storage_path=storage_path, filename=filename)
    headers = {
        "content-disposition": f'attachment; filename="{filename}"',
        "content-encoding": "identity",
    }
    if size_bytes is not None:
        headers["accept-ranges"] = "bytes"
    if checksum_sha256 is not None:
        headers["etag"] = f'"{checksum_sha256}"'

    status_code = status.HTTP_200_OK
    iterator_kwargs: dict[str, int] = {}
    if byte_range is not None:
        start, end = byte_range
        iterator_kwargs = {"start": start, "end": end}
        length = end - start + 1
        headers["content-length"] = str(length)
        if size_bytes is not None:
            headers["content-range"] = f"bytes {start}-{end}/{size_bytes}"
        status_code = status.HTTP_206_PARTIAL_CONTENT
    elif size_bytes is not None:
        headers["content-length"] = str(size_bytes)

    return StreamingResponse(
        object_store.iter_bytes(storage_path, **iterator_kwargs),
        media_type=media_type,
        headers=headers,
        status_code=status_code,
    )


def _parse_range_header(
    range_header: str | None,
    *,
    size_bytes: int | None,
) -> tuple[int, int] | None:
    if range_header is None or size_bytes is None:
        return None

    value = range_header.strip()
    if not value:
        return None
    if not value.startswith("bytes="):
        raise ApiError(
            code="asset_range_invalid",
            message="Only byte range requests are supported for asset downloads",
            status_code=HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
            details={"range": value},
        )

    spec = value[6:]
    if "," in spec or "-" not in spec:
        raise ApiError(
            code="asset_range_invalid",
            message="Only a single byte range is supported for asset downloads",
            status_code=HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
            details={"range": value},
        )

    start_text, end_text = spec.split("-", 1)
    if start_text == "":
        try:
            suffix_length = int(end_text)
        except ValueError as exc:
            raise ApiError(
                code="asset_range_invalid",
                message="Byte range header is malformed",
                status_code=HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
                details={"range": value},
            ) from exc
        if suffix_length <= 0:
            raise ApiError(
                code="asset_range_invalid",
                message="Byte range header is malformed",
                status_code=HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
                details={"range": value},
            )
        if suffix_length >= size_bytes:
            return 0, size_bytes - 1
        return size_bytes - suffix_length, size_bytes - 1

    try:
        start = int(start_text)
        end = size_bytes - 1 if end_text == "" else int(end_text)
    except ValueError as exc:
        raise ApiError(
            code="asset_range_invalid",
            message="Byte range header is malformed",
            status_code=HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
            details={"range": value},
        ) from exc

    if start < 0 or end < start or start >= size_bytes:
        raise ApiError(
            code="asset_range_invalid",
            message="Requested byte range is outside the available asset size",
            status_code=HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
            details={"range": value, "size_bytes": size_bytes},
        )

    return start, min(end, size_bytes - 1)


def _reader_model_response(
    *,
    request: Request,
    project_id: str,
    artifact: ReaderModelArtifact,
) -> ReaderModelResponse:
    object_store = get_object_store()
    if not object_store.exists(artifact.storage_path):
        raise _artifact_storage_missing_error(
            storage_path=artifact.storage_path,
            filename=f"reader-model-{project_id}.json",
        )
    model = object_store.read_json(artifact.storage_path)
    return ReaderModelResponse(
        project_id=UUID(project_id),
        asset_id=UUID(artifact.asset_id),
        version=artifact.version,
        status=artifact.status,
        download_url=_download_url(
            request,
            "download_reader_model_route",
            project_id=project_id,
        ),
        model=model,
    )


def _transcript_response(
    *,
    request: Request,
    project_id: str,
    artifact: TranscriptArtifact,
) -> TranscriptArtifactResponse:
    object_store = get_object_store()
    if not object_store.exists(artifact.storage_path):
        raise _artifact_storage_missing_error(
            storage_path=artifact.storage_path,
            filename=f"transcript-{artifact.job_id}.json",
        )
    payload = object_store.read_json(artifact.storage_path)
    return TranscriptArtifactResponse(
        project_id=UUID(project_id),
        job_id=UUID(artifact.job_id),
        version=artifact.version,
        status=artifact.status,
        download_url=_download_url(
            request,
            "download_transcript_route",
            project_id=project_id,
            job_id=artifact.job_id,
        ),
        language=artifact.language,
        segment_count=artifact.segment_count,
        word_count=artifact.word_count,
        payload=payload,
    )


def _match_response(
    *,
    request: Request,
    project_id: str,
    artifact: MatchArtifact,
) -> MatchArtifactResponse:
    object_store = get_object_store()
    if not object_store.exists(artifact.storage_path):
        raise _artifact_storage_missing_error(
            storage_path=artifact.storage_path,
            filename=f"match-{artifact.job_id}.json",
        )
    payload = object_store.read_json(artifact.storage_path)
    return MatchArtifactResponse(
        project_id=UUID(project_id),
        job_id=UUID(artifact.job_id),
        version=artifact.version,
        status=artifact.status,
        download_url=_download_url(
            request,
            "download_match_route",
            project_id=project_id,
            job_id=artifact.job_id,
        ),
        match_count=artifact.match_count,
        gap_count=artifact.gap_count,
        average_confidence=artifact.average_confidence,
        payload=payload,
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


@router.get("", response_model=ProjectListResponse)
async def list_projects_route(session: DbSession) -> ProjectListResponse:
    projects = list(
        session.scalars(
            select(Project).order_by(Project.updated_at.desc(), Project.created_at.desc())
        )
    )
    return ProjectListResponse(
        projects=[
            _project_list_item(
                project,
                get_latest_job(session=session, project_id=project.id),
            )
            for project in projects
        ],
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
    request: Request,
    session: DbSession,
) -> AssetCreateResponse:
    object_store = get_object_store()
    filename = file.filename or "upload.bin"
    content_type = file.content_type or "application/octet-stream"
    size_limit_bytes = _upload_size_limit_bytes()
    if size_limit_bytes is not None:
        content_length_header = request.headers.get("content-length")
        request_content_length: int | None = None
        if content_length_header:
            try:
                request_content_length = int(content_length_header)
            except ValueError:
                request_content_length = None
            else:
                if request_content_length > size_limit_bytes:
                    _raise_upload_too_large(
                        filename=filename,
                        max_size_bytes=size_limit_bytes,
                        request_content_length_bytes=request_content_length,
                    )

    payload = await file.read()
    if size_limit_bytes is not None and len(payload) > size_limit_bytes:
        _raise_upload_too_large(
            filename=filename,
            max_size_bytes=size_limit_bytes,
            size_bytes=len(payload),
        )
    _validate_upload_metadata(
        filename=filename,
        content_type=content_type,
        payload=payload,
    )
    try:
        asset = store_uploaded_asset(
            session=session,
            project_id=project_id,
            kind=kind,
            filename=filename,
            content_type=content_type,
            payload=payload,
            object_store=object_store,
        )
    except ApiError:
        raise
    except Exception as exc:
        raise ApiError(
            code="asset_upload_failed",
            message="Sync could not store the uploaded asset",
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            details={
                "filename": filename,
                "error_type": type(exc).__name__,
            },
        ) from exc
    if kind == "epub":
        try:
            generate_reader_model_artifact(
                session=session,
                project_id=project_id,
                asset=asset,
                object_store=object_store,
            )
        except ApiError:
            raise
        except Exception as exc:
            asset.status = "invalid"
            session.add(asset)
            session.commit()
            raise ApiError(
                code="epub_processing_failed",
                message="The EPUB uploaded, but Sync could not generate a reader model from it",
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                details={
                    "asset_id": asset.id,
                    "error_type": type(exc).__name__,
                },
            ) from exc
    return AssetCreateResponse(
        asset_id=UUID(asset.id),
        upload_mode=asset.upload_mode,
        status=asset.status,
    )


@router.get("/{project_id}/assets/{asset_id}/content")
async def get_asset_content_route(
    project_id: str,
    asset_id: str,
    request: Request,
    session: DbSession,
) -> StreamingResponse:
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

    byte_range = _parse_range_header(
        request.headers.get("range"),
        size_bytes=asset.size_bytes,
    )
    return _content_response(
        storage_path=asset.storage_path,
        media_type=asset.content_type,
        filename=asset.filename,
        size_bytes=asset.size_bytes,
        checksum_sha256=asset.checksum_sha256,
        byte_range=byte_range,
    )


@router.post(
    "/{project_id}/jobs",
    status_code=status.HTTP_201_CREATED,
    response_model=JobCreateResponse,
)
async def create_job_route(
    project_id: str,
    payload: JobCreateRequest,
    background_tasks: BackgroundTasks,
    session: DbSession,
) -> JobCreateResponse:
    result = create_alignment_job(
        session=session,
        project_id=project_id,
        book_asset_id=parse_uuid(payload.book_asset_id),
        audio_asset_ids=[parse_uuid(asset_id) for asset_id in payload.audio_asset_ids],
    )
    job = result.job
    if not result.reused_existing:
        await broker.broadcast(
            project_id=project_id,
            event_type="job.queued",
            job_id=job.id,
            payload={"stage": job.progress_stage, "percent": job.progress_percent},
        )
        settings = get_settings()
        if settings.app_env != "test":
            try:
                if settings.use_inline_job_execution:
                    background_tasks.add_task(run_alignment_job_inline, project_id, job.id)
                else:
                    run_alignment_job_task.delay(project_id, job.id)
            except Exception as exc:
                failed_job = mark_job_enqueue_failed(
                    session=session,
                    project_id=project_id,
                    job_id=job.id,
                )
                await broker.broadcast(
                    project_id=project_id,
                    event_type="job.failed",
                    job_id=failed_job.id,
                    payload={
                        "stage": failed_job.progress_stage,
                        "percent": failed_job.progress_percent,
                        "terminal_reason": failed_job.terminal_reason,
                    },
                )
                raise ApiError(
                    code="job_dispatch_failed",
                    message="Sync could not start background processing for this job",
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    details={
                        "job_id": job.id,
                        "error_type": type(exc).__name__,
                    },
                ) from exc
    return JobCreateResponse(
        job_id=UUID(job.id),
        status=job.status,
        reused_existing=result.reused_existing,
        attempt_number=job.attempt_number,
        retry_of_job_id=_as_uuid(job.retry_of_job_id),
    )


@router.get("/{project_id}/jobs", response_model=ProjectJobHistoryResponse)
async def list_jobs_route(project_id: str, session: DbSession) -> ProjectJobHistoryResponse:
    get_project_or_404(session=session, project_id=project_id)
    jobs = list(
        session.scalars(
            select(AlignmentJob)
            .where(AlignmentJob.project_id == project_id)
            .order_by(AlignmentJob.updated_at.desc(), AlignmentJob.created_at.desc())
        )
    )
    return ProjectJobHistoryResponse(
        project_id=UUID(project_id),
        jobs=[_job_history_entry(job) for job in jobs],
    )


@router.get("/{project_id}", response_model=ProjectDetailResponse)
async def get_project_route(
    project_id: str,
    request: Request,
    session: DbSession,
) -> ProjectDetailResponse:
    project = get_project_or_404(session=session, project_id=project_id)
    latest_job = get_latest_job(session=session, project_id=project_id)
    assets = []
    for asset in sorted(project.assets, key=lambda asset: asset.created_at):
        summary = _asset_summary(asset)
        if asset.storage_path is not None:
            summary.download_url = str(
                request.url_for(
                    "get_asset_content_route",
                    project_id=project_id,
                    asset_id=asset.id,
                )
            )
        assets.append(summary)
    return ProjectDetailResponse(
        project_id=UUID(project.id),
        title=project.title,
        language=project.language,
        status=project.status,
        created_at=project.created_at,
        updated_at=project.updated_at,
        assets=assets,
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
    request: Request,
    session: DbSession,
) -> TranscriptArtifactResponse:
    get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    artifact = get_transcript_artifact_or_404(
        session=session,
        project_id=project_id,
        job_id=job_id,
    )
    return _transcript_response(request=request, project_id=project_id, artifact=artifact)


@router.get(
    "/{project_id}/jobs/{job_id}/matches",
    response_model=MatchArtifactResponse,
)
async def get_match_route(
    project_id: str,
    job_id: str,
    request: Request,
    session: DbSession,
) -> MatchArtifactResponse:
    get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    artifact = get_match_artifact_or_404(
        session=session,
        project_id=project_id,
        job_id=job_id,
    )
    return _match_response(request=request, project_id=project_id, artifact=artifact)


@router.get("/{project_id}/sync", response_model=SyncArtifactResponse)
async def get_sync_route(
    project_id: str,
    request: Request,
    session: DbSession,
) -> SyncArtifactResponse:
    get_project_or_404(session=session, project_id=project_id)
    artifact = get_latest_sync_artifact(session=session, project_id=project_id)
    response = _sync_response(project_id, artifact)
    if response.download_url is None and artifact.storage_path is not None:
        response.download_url = _download_url(
            request,
            "download_sync_route",
            project_id=project_id,
        )
    return response


@router.get("/{project_id}/reader-model", response_model=ReaderModelResponse)
async def get_reader_model_route(
    project_id: str,
    request: Request,
    session: DbSession,
) -> ReaderModelResponse:
    get_project_or_404(session=session, project_id=project_id)
    artifact = get_reader_model_artifact_or_404(session=session, project_id=project_id)
    return _reader_model_response(request=request, project_id=project_id, artifact=artifact)


@router.get("/{project_id}/sync/content", name="download_sync_route")
async def download_sync_route(project_id: str, session: DbSession) -> StreamingResponse:
    get_project_or_404(session=session, project_id=project_id)
    artifact = get_latest_sync_artifact(session=session, project_id=project_id)
    return _content_response(
        storage_path=artifact.storage_path,
        media_type="application/json",
        filename=f"sync-{project_id}.json",
        size_bytes=artifact.size_bytes,
    )


@router.get("/{project_id}/reader-model/content", name="download_reader_model_route")
async def download_reader_model_route(
    project_id: str,
    session: DbSession,
) -> StreamingResponse:
    get_project_or_404(session=session, project_id=project_id)
    artifact = get_reader_model_artifact_or_404(session=session, project_id=project_id)
    return _content_response(
        storage_path=artifact.storage_path,
        media_type="application/json",
        filename=f"reader-model-{project_id}.json",
        size_bytes=artifact.size_bytes,
    )


@router.get(
    "/{project_id}/jobs/{job_id}/transcript/content",
    name="download_transcript_route",
)
async def download_transcript_route(
    project_id: str,
    job_id: str,
    session: DbSession,
) -> StreamingResponse:
    get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    artifact = get_transcript_artifact_or_404(
        session=session,
        project_id=project_id,
        job_id=job_id,
    )
    return _content_response(
        storage_path=artifact.storage_path,
        media_type="application/json",
        filename=f"transcript-{job_id}.json",
        size_bytes=artifact.size_bytes,
    )


@router.get("/{project_id}/jobs/{job_id}/matches/content", name="download_match_route")
async def download_match_route(
    project_id: str,
    job_id: str,
    session: DbSession,
) -> StreamingResponse:
    get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    artifact = get_match_artifact_or_404(
        session=session,
        project_id=project_id,
        job_id=job_id,
    )
    return _content_response(
        storage_path=artifact.storage_path,
        media_type="application/json",
        filename=f"match-{job_id}.json",
        size_bytes=artifact.size_bytes,
    )


@router.post("/{project_id}/jobs/{job_id}/cancel", response_model=JobCreateResponse)
async def cancel_job_route(project_id: str, job_id: str, session: DbSession) -> JobCreateResponse:
    existing_job = get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    if existing_job.status == "cancelled":
        return JobCreateResponse(
            job_id=UUID(existing_job.id),
            status=existing_job.status,
            reused_existing=True,
            attempt_number=existing_job.attempt_number,
            retry_of_job_id=_as_uuid(existing_job.retry_of_job_id),
        )
    job = cancel_job(session=session, project_id=project_id, job_id=job_id)
    await broker.broadcast(
        project_id=project_id,
        event_type="job.cancelled",
        job_id=job.id,
        payload={"stage": job.progress_stage, "percent": job.progress_percent},
    )
    return JobCreateResponse(
        job_id=UUID(job.id),
        status=job.status,
        reused_existing=False,
        attempt_number=job.attempt_number,
        retry_of_job_id=_as_uuid(job.retry_of_job_id),
    )
