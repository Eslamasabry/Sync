from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import JSON, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def utc_now() -> datetime:
    return datetime.now(UTC)


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

    project: Mapped[Project] = relationship(back_populates="assets")


class AlignmentJob(Base, TimestampMixin):
    __tablename__ = "alignment_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    project_id: Mapped[str] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"),
        index=True,
    )
    job_type: Mapped[str] = mapped_column(String(32))
    status: Mapped[str] = mapped_column(String(32), default="queued")
    book_asset_id: Mapped[str] = mapped_column(ForeignKey("assets.id"))
    audio_asset_ids: Mapped[list[str]] = mapped_column(JSON, default=list)
    progress_stage: Mapped[str | None] = mapped_column(String(64), nullable=True)
    progress_percent: Mapped[int] = mapped_column(Integer, default=0)
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
