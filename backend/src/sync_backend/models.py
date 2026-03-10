from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import JSON, DateTime, ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def utc_now() -> datetime:
    return datetime.now(UTC)


class ProjectLifecyclePhase(StrEnum):
    DRAFT = "draft"
    READY_TO_ALIGN = "ready_to_align"
    ALIGNING = "aligning"
    READY_TO_READ = "ready_to_read"
    ATTENTION_NEEDED = "attention_needed"


class ProjectLifecycleAction(StrEnum):
    ATTACH_EPUB = "attach_epub"
    ATTACH_AUDIO = "attach_audio"
    START_ALIGNMENT = "start_alignment"
    MONITOR_ALIGNMENT = "monitor_alignment"
    OPEN_READER = "open_reader"
    RETRY_ALIGNMENT = "retry_alignment"


class ProjectLifecycleRequirement(StrEnum):
    EPUB = "epub"
    AUDIO = "audio"


@dataclass(frozen=True, slots=True)
class DerivedProjectLifecycle:
    phase: ProjectLifecyclePhase
    next_action: ProjectLifecycleAction
    missing_requirements: tuple[ProjectLifecycleRequirement, ...] = ()
    is_readable: bool = False


_PROJECT_STATUS_TO_PHASE: dict[str, ProjectLifecyclePhase] = {
    "created": ProjectLifecyclePhase.DRAFT,
    "draft": ProjectLifecyclePhase.DRAFT,
    "ready": ProjectLifecyclePhase.READY_TO_ALIGN,
    "ready_to_align": ProjectLifecyclePhase.READY_TO_ALIGN,
    "queued": ProjectLifecyclePhase.ALIGNING,
    "running": ProjectLifecyclePhase.ALIGNING,
    "processing": ProjectLifecyclePhase.ALIGNING,
    "aligning": ProjectLifecyclePhase.ALIGNING,
    "completed": ProjectLifecyclePhase.READY_TO_READ,
    "ready_to_read": ProjectLifecyclePhase.READY_TO_READ,
    "failed": ProjectLifecyclePhase.ATTENTION_NEEDED,
    "cancelled": ProjectLifecyclePhase.ATTENTION_NEEDED,
    "canceled": ProjectLifecyclePhase.ATTENTION_NEEDED,
    "attention_needed": ProjectLifecyclePhase.ATTENTION_NEEDED,
}

_JOB_STATUS_TO_PHASE: dict[str, ProjectLifecyclePhase] = {
    "queued": ProjectLifecyclePhase.ALIGNING,
    "running": ProjectLifecyclePhase.ALIGNING,
    "completed": ProjectLifecyclePhase.READY_TO_READ,
    "failed": ProjectLifecyclePhase.ATTENTION_NEEDED,
    "cancelled": ProjectLifecyclePhase.ATTENTION_NEEDED,
    "canceled": ProjectLifecyclePhase.ATTENTION_NEEDED,
}


def _next_action_for_missing_requirements(
    missing_requirements: tuple[ProjectLifecycleRequirement, ...],
) -> ProjectLifecycleAction:
    if ProjectLifecycleRequirement.EPUB in missing_requirements:
        return ProjectLifecycleAction.ATTACH_EPUB
    return ProjectLifecycleAction.ATTACH_AUDIO


def derive_project_lifecycle(
    *,
    project_status: str | None,
    asset_kinds: Iterable[str] = (),
    latest_job_status: str | None = None,
) -> DerivedProjectLifecycle:
    normalized_asset_kinds = {kind.strip().casefold() for kind in asset_kinds if kind}
    missing_requirements = tuple(
        requirement
        for requirement, required_kind in (
            (ProjectLifecycleRequirement.EPUB, "epub"),
            (ProjectLifecycleRequirement.AUDIO, "audio"),
        )
        if required_kind not in normalized_asset_kinds
    )

    normalized_job_status = latest_job_status.strip().casefold() if latest_job_status else None
    if normalized_job_status in _JOB_STATUS_TO_PHASE:
        phase = _JOB_STATUS_TO_PHASE[normalized_job_status]
        return DerivedProjectLifecycle(
            phase=phase,
            next_action=(
                ProjectLifecycleAction.MONITOR_ALIGNMENT
                if phase == ProjectLifecyclePhase.ALIGNING
                else ProjectLifecycleAction.OPEN_READER
                if phase == ProjectLifecyclePhase.READY_TO_READ
                else ProjectLifecycleAction.RETRY_ALIGNMENT
            ),
            missing_requirements=missing_requirements,
            is_readable=phase == ProjectLifecyclePhase.READY_TO_READ,
        )

    if missing_requirements:
        return DerivedProjectLifecycle(
            phase=ProjectLifecyclePhase.DRAFT,
            next_action=_next_action_for_missing_requirements(missing_requirements),
            missing_requirements=missing_requirements,
            is_readable=False,
        )

    normalized_project_status = project_status.strip().casefold() if project_status else None
    lifecycle_phase: ProjectLifecyclePhase | None = (
        _PROJECT_STATUS_TO_PHASE.get(normalized_project_status)
        if normalized_project_status is not None
        else None
    )
    if lifecycle_phase is None or lifecycle_phase == ProjectLifecyclePhase.DRAFT:
        lifecycle_phase = ProjectLifecyclePhase.READY_TO_ALIGN

    next_action = {
        ProjectLifecyclePhase.DRAFT: _next_action_for_missing_requirements(missing_requirements),
        ProjectLifecyclePhase.READY_TO_ALIGN: ProjectLifecycleAction.START_ALIGNMENT,
        ProjectLifecyclePhase.ALIGNING: ProjectLifecycleAction.MONITOR_ALIGNMENT,
        ProjectLifecyclePhase.READY_TO_READ: ProjectLifecycleAction.OPEN_READER,
        ProjectLifecyclePhase.ATTENTION_NEEDED: ProjectLifecycleAction.RETRY_ALIGNMENT,
    }[lifecycle_phase]
    return DerivedProjectLifecycle(
        phase=lifecycle_phase,
        next_action=next_action,
        missing_requirements=missing_requirements,
        is_readable=lifecycle_phase == ProjectLifecyclePhase.READY_TO_READ,
    )


class Base(DeclarativeBase):
    pass


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=utc_now,
        onupdate=utc_now,
    )


class Project(Base, TimestampMixin):
    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    title: Mapped[str] = mapped_column(String(255))
    language: Mapped[str | None] = mapped_column(String(32), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="created")

    assets: Mapped[list[Asset]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
    )
    jobs: Mapped[list[AlignmentJob]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
    )
    sync_artifacts: Mapped[list[SyncArtifact]] = relationship(
        back_populates="project",
        cascade="all, delete-orphan",
    )


class Asset(Base, TimestampMixin):
    __tablename__ = "assets"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    project_id: Mapped[str] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"),
        index=True,
    )
    kind: Mapped[str] = mapped_column(String(32))
    filename: Mapped[str] = mapped_column(String(255))
    content_type: Mapped[str] = mapped_column(String(255))
    upload_mode: Mapped[str] = mapped_column(String(32), default="multipart")
    status: Mapped[str] = mapped_column(String(32), default="uploading")
    storage_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    checksum_sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)

    project: Mapped[Project] = relationship(back_populates="assets")


class AlignmentJob(Base, TimestampMixin):
    __tablename__ = "alignment_jobs"
    __table_args__ = (
        Index(
            "ux_alignment_jobs_active_request_fingerprint",
            "project_id",
            "request_fingerprint",
            unique=True,
            sqlite_where=text("status IN ('queued', 'running', 'completed')"),
            postgresql_where=text("status IN ('queued', 'running', 'completed')"),
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    project_id: Mapped[str] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"),
        index=True,
    )
    job_type: Mapped[str] = mapped_column(String(32))
    status: Mapped[str] = mapped_column(String(32), default="queued")
    book_asset_id: Mapped[str] = mapped_column(ForeignKey("assets.id"))
    audio_asset_ids: Mapped[list[str]] = mapped_column(JSON, default=list)
    request_fingerprint: Mapped[str] = mapped_column(String(128), index=True)
    attempt_number: Mapped[int] = mapped_column(Integer, default=1)
    retry_of_job_id: Mapped[str | None] = mapped_column(
        ForeignKey("alignment_jobs.id", ondelete="SET NULL"),
        nullable=True,
    )
    progress_stage: Mapped[str | None] = mapped_column(String(64), nullable=True)
    progress_percent: Mapped[int] = mapped_column(Integer, default=0)
    terminal_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    match_confidence: Mapped[float | None] = mapped_column(nullable=True)
    mismatch_ranges: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)

    project: Mapped[Project] = relationship(back_populates="jobs")


class SyncArtifact(Base, TimestampMixin):
    __tablename__ = "sync_artifacts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    project_id: Mapped[str] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"),
        index=True,
    )
    job_id: Mapped[str | None] = mapped_column(
        ForeignKey("alignment_jobs.id", ondelete="SET NULL"),
        nullable=True,
    )
    version: Mapped[str] = mapped_column(String(16), default="1.0")
    status: Mapped[str] = mapped_column(String(32), default="pending")
    download_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    inline_payload: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    storage_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(Integer, nullable=True)

    project: Mapped[Project] = relationship(back_populates="sync_artifacts")


class ReaderModelArtifact(Base, TimestampMixin):
    __tablename__ = "reader_model_artifacts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    project_id: Mapped[str] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"),
        index=True,
    )
    asset_id: Mapped[str] = mapped_column(ForeignKey("assets.id", ondelete="CASCADE"))
    version: Mapped[str] = mapped_column(String(16), default="1.0")
    status: Mapped[str] = mapped_column(String(32), default="generated")
    storage_path: Mapped[str] = mapped_column(Text)
    size_bytes: Mapped[int] = mapped_column(Integer)


class TranscriptArtifact(Base, TimestampMixin):
    __tablename__ = "transcript_artifacts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    project_id: Mapped[str] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"),
        index=True,
    )
    job_id: Mapped[str] = mapped_column(ForeignKey("alignment_jobs.id", ondelete="CASCADE"))
    version: Mapped[str] = mapped_column(String(16), default="1.0")
    status: Mapped[str] = mapped_column(String(32), default="generated")
    language: Mapped[str | None] = mapped_column(String(32), nullable=True)
    segment_count: Mapped[int] = mapped_column(Integer, default=0)
    word_count: Mapped[int] = mapped_column(Integer, default=0)
    storage_path: Mapped[str] = mapped_column(Text)
    size_bytes: Mapped[int] = mapped_column(Integer)


class MatchArtifact(Base, TimestampMixin):
    __tablename__ = "match_artifacts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    project_id: Mapped[str] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"),
        index=True,
    )
    job_id: Mapped[str] = mapped_column(ForeignKey("alignment_jobs.id", ondelete="CASCADE"))
    version: Mapped[str] = mapped_column(String(16), default="1.0")
    status: Mapped[str] = mapped_column(String(32), default="generated")
    match_count: Mapped[int] = mapped_column(Integer, default=0)
    gap_count: Mapped[int] = mapped_column(Integer, default=0)
    average_confidence: Mapped[float | None] = mapped_column(nullable=True)
    storage_path: Mapped[str] = mapped_column(Text)
    size_bytes: Mapped[int] = mapped_column(Integer)
