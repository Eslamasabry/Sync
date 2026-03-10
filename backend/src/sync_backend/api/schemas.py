from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from sync_backend.models import (
    ProjectLifecycleAction,
    ProjectLifecyclePhase,
    ProjectLifecycleRequirement,
    derive_project_lifecycle,
)


class ProjectLifecycleResponse(BaseModel):
    phase: ProjectLifecyclePhase
    next_action: ProjectLifecycleAction
    missing_requirements: list[ProjectLifecycleRequirement] = Field(default_factory=list)
    is_readable: bool = False


class ProjectCreateRequest(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    language: str | None = Field(default=None, max_length=32)


class ProjectCreateResponse(BaseModel):
    project_id: UUID
    status: str
    created_at: datetime
    lifecycle: ProjectLifecycleResponse | None = None

    @model_validator(mode="after")
    def populate_lifecycle(self) -> "ProjectCreateResponse":
        if self.lifecycle is None:
            derived = derive_project_lifecycle(project_status=self.status)
            self.lifecycle = ProjectLifecycleResponse(
                phase=derived.phase,
                next_action=derived.next_action,
                missing_requirements=list(derived.missing_requirements),
                is_readable=derived.is_readable,
            )
        return self


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
    reused_existing: bool = False
    attempt_number: int = Field(ge=1)
    retry_of_job_id: UUID | None = None


class AssetSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    asset_id: UUID
    kind: str
    filename: str
    content_type: str
    upload_mode: str
    status: str
    size_bytes: int | None = Field(default=None, ge=0)
    checksum_sha256: str | None = Field(default=None, min_length=64, max_length=64)
    duration_ms: int | None = Field(default=None, ge=0)
    download_url: str | None = None
    created_at: datetime


class JobProgress(BaseModel):
    stage: str | None
    percent: int = Field(ge=0, le=100)


class JobQuality(BaseModel):
    match_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    mismatch_ranges: list[dict[str, Any]]


class JobSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    job_id: UUID
    job_type: str
    status: str
    attempt_number: int = Field(ge=1)
    retry_of_job_id: UUID | None = None
    terminal_reason: str | None = None
    created_at: datetime
    updated_at: datetime


class ProjectListItemResponse(BaseModel):
    project_id: UUID
    title: str
    language: str | None
    status: str
    updated_at: datetime
    asset_count: int = Field(ge=0)
    audio_asset_count: int = Field(ge=0)
    latest_job: JobSummary | None = None
    lifecycle: ProjectLifecycleResponse | None = None

    @model_validator(mode="after")
    def populate_lifecycle(self) -> "ProjectListItemResponse":
        if self.lifecycle is None:
            inferred_asset_kinds: list[str] = []
            if self.asset_count > self.audio_asset_count:
                inferred_asset_kinds.append("epub")
            if self.audio_asset_count > 0:
                inferred_asset_kinds.append("audio")
            derived = derive_project_lifecycle(
                project_status=self.status,
                asset_kinds=inferred_asset_kinds,
                latest_job_status=self.latest_job.status if self.latest_job else None,
            )
            self.lifecycle = ProjectLifecycleResponse(
                phase=derived.phase,
                next_action=derived.next_action,
                missing_requirements=list(derived.missing_requirements),
                is_readable=derived.is_readable,
            )
        return self


class ProjectListResponse(BaseModel):
    projects: list[ProjectListItemResponse]


class ProjectDetailResponse(BaseModel):
    project_id: UUID
    title: str
    language: str | None
    status: str
    created_at: datetime
    updated_at: datetime
    assets: list[AssetSummary]
    latest_job: JobSummary | None
    lifecycle: ProjectLifecycleResponse | None = None

    @model_validator(mode="after")
    def populate_lifecycle(self) -> "ProjectDetailResponse":
        if self.lifecycle is None:
            derived = derive_project_lifecycle(
                project_status=self.status,
                asset_kinds=[asset.kind for asset in self.assets],
                latest_job_status=self.latest_job.status if self.latest_job else None,
            )
            self.lifecycle = ProjectLifecycleResponse(
                phase=derived.phase,
                next_action=derived.next_action,
                missing_requirements=list(derived.missing_requirements),
                is_readable=derived.is_readable,
            )
        return self


class JobHistoryEntryResponse(BaseModel):
    job_id: UUID
    job_type: str
    status: str
    progress: JobProgress
    request_fingerprint: str
    attempt_number: int = Field(ge=1)
    retry_of_job_id: UUID | None = None
    terminal_reason: str | None = None
    created_at: datetime
    updated_at: datetime


class ProjectJobHistoryResponse(BaseModel):
    project_id: UUID
    jobs: list[JobHistoryEntryResponse]


class JobDetailResponse(BaseModel):
    job_id: UUID
    status: str
    progress: JobProgress
    quality: JobQuality
    request_fingerprint: str
    attempt_number: int = Field(ge=1)
    retry_of_job_id: UUID | None = None
    terminal_reason: str | None = None
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


class ReaderModelResponse(BaseModel):
    project_id: UUID
    asset_id: UUID
    version: str
    status: str
    download_url: str | None = None
    model: dict[str, Any]


class TranscriptArtifactResponse(BaseModel):
    project_id: UUID
    job_id: UUID
    version: str
    status: str
    download_url: str | None = None
    language: str | None
    segment_count: int = Field(ge=0)
    word_count: int = Field(ge=0)
    payload: dict[str, Any]


class MatchArtifactResponse(BaseModel):
    project_id: UUID
    job_id: UUID
    version: str
    status: str
    download_url: str | None = None
    match_count: int = Field(ge=0)
    gap_count: int = Field(ge=0)
    average_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    payload: dict[str, Any]


class EventEnvelope(BaseModel):
    type: str
    project_id: UUID
    job_id: UUID | None = None
    timestamp: datetime
    payload: dict[str, Any]
