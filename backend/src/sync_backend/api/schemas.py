from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ProjectCreateRequest(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    language: str | None = Field(default=None, max_length=32)


class ProjectCreateResponse(BaseModel):
    project_id: UUID
    status: str
    created_at: datetime


class AssetCreateRequest(BaseModel):
    kind: Literal["epub", "audio"]
    filename: str = Field(min_length=1, max_length=255)
    content_type: str = Field(min_length=1, max_length=255)


class AssetCreateResponse(BaseModel):
    asset_id: UUID
    upload_mode: str
    status: str


class JobCreateRequest(BaseModel):
    job_type: Literal["alignment"]
    audio_asset_ids: list[UUID] = Field(min_length=1)
    book_asset_id: UUID


class JobCreateResponse(BaseModel):
    job_id: UUID
    status: str


class AssetSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    asset_id: UUID
    kind: str
    filename: str
    content_type: str
    upload_mode: str
    status: str
    created_at: datetime


class JobProgress(BaseModel):
    stage: str | None
    percent: int


class JobQuality(BaseModel):
    match_confidence: float | None
    mismatch_ranges: list[dict[str, Any]]


class JobSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    job_id: UUID
    job_type: str
    status: str
    created_at: datetime
    updated_at: datetime


class ProjectDetailResponse(BaseModel):
    project_id: UUID
    title: str
    language: str | None
    status: str
    created_at: datetime
    updated_at: datetime
    assets: list[AssetSummary]
    latest_job: JobSummary | None


class JobDetailResponse(BaseModel):
    job_id: UUID
    status: str
    progress: JobProgress
    quality: JobQuality
    book_asset_id: UUID
    audio_asset_ids: list[UUID]
    created_at: datetime
    updated_at: datetime


class SyncArtifactResponse(BaseModel):
    project_id: UUID
    job_id: UUID | None
    version: str
    status: str
    download_url: str | None
    inline_payload: dict[str, Any] | None
    created_at: datetime
    updated_at: datetime


class EventEnvelope(BaseModel):
    type: str
    project_id: UUID
    job_id: UUID | None = None
    timestamp: datetime
    payload: dict[str, Any]
