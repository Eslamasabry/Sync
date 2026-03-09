from __future__ import annotations

from typing import Any
from uuid import uuid4

from sqlalchemy.orm import Session

from sync_backend.api.realtime import publish_project_event_sync
from sync_backend.models import SyncArtifact
from sync_backend.services import (
    get_job_or_404,
    get_match_artifact_or_404,
    get_project_or_404,
    get_transcript_artifact_or_404,
)
from sync_backend.storage import ObjectStore


def _build_audio_manifest(transcript_payload: dict[str, Any]) -> list[dict[str, int | str]]:
    durations_by_asset: dict[str, int] = {}
    ordered_asset_ids: list[str] = []

    for segment in transcript_payload.get("segments", []):
        asset_id = str(segment["asset_id"])
        if asset_id not in durations_by_asset:
            ordered_asset_ids.append(asset_id)
            durations_by_asset[asset_id] = 0
        durations_by_asset[asset_id] = max(durations_by_asset[asset_id], int(segment["end_ms"]))

    manifest: list[dict[str, int | str]] = []
    running_offset_ms = 0
    for asset_id in ordered_asset_ids:
        duration_ms = durations_by_asset[asset_id]
        manifest.append(
            {
                "asset_id": asset_id,
                "offset_ms": running_offset_ms,
                "duration_ms": duration_ms,
            }
        )
        running_offset_ms += duration_ms
    return manifest


def _collapse_gaps(match_payload: dict[str, Any]) -> list[dict[str, int | str]]:
    collapsed: list[dict[str, int | str]] = []
    for gap in sorted(match_payload.get("gaps", []), key=lambda item: int(item["start_ms"])):
        if (
            collapsed
            and collapsed[-1]["reason"] == gap["reason"]
            and int(gap["start_ms"]) <= int(collapsed[-1]["end_ms"]) + 1
        ):
            collapsed[-1]["end_ms"] = max(int(collapsed[-1]["end_ms"]), int(gap["end_ms"]))
            collapsed[-1]["transcript_end_index"] = int(gap["transcript_index"])
            collapsed[-1]["word_count"] = int(collapsed[-1]["word_count"]) + 1
            continue

        collapsed.append(
            {
                "start_ms": int(gap["start_ms"]),
                "end_ms": int(gap["end_ms"]),
                "reason": str(gap["reason"]),
                "transcript_start_index": int(gap["transcript_index"]),
                "transcript_end_index": int(gap["transcript_index"]),
                "word_count": 1,
            }
        )
    return collapsed


def _build_sync_stats(
    *,
    tokens: list[dict[str, Any]],
    gaps: list[dict[str, int | str]],
    match_payload: dict[str, Any],
) -> dict[str, float | int | None]:
    matched_word_count = len(tokens)
    unmatched_word_count = sum(int(gap["word_count"]) for gap in gaps)
    transcript_word_count = matched_word_count + unmatched_word_count
    content_duration_ms = (
        int(tokens[-1]["end_ms"]) - int(tokens[0]["start_ms"])
        if matched_word_count > 0
        else 0
    )
    low_confidence_token_count = sum(
        1 for token in tokens if float(token["confidence"]) < 0.85
    )

    return {
        "matched_word_count": matched_word_count,
        "unmatched_word_count": unmatched_word_count,
        "transcript_word_count": transcript_word_count,
        "coverage_ratio": (
            round(matched_word_count / transcript_word_count, 4)
            if transcript_word_count > 0
            else None
        ),
        "average_confidence": match_payload.get("average_confidence"),
        "low_confidence_token_count": low_confidence_token_count,
        "content_duration_ms": content_duration_ms,
    }


def build_sync_payload(
    *,
    project_id: str,
    language: str | None,
    transcript_payload: dict[str, Any],
    match_payload: dict[str, Any],
) -> dict[str, Any]:
    tokens = [
        {
            "id": token_id,
            "text": match["word"],
            "normalized": match["normalized"],
            "start_ms": match["start_ms"],
            "end_ms": match["end_ms"],
            "confidence": match["confidence"],
            "location": match["location"],
        }
        for token_id, match in enumerate(
            sorted(match_payload.get("matches", []), key=lambda item: int(item["start_ms"]))
        )
    ]
    gaps = _collapse_gaps(match_payload)

    return {
        "version": "1.0",
        "book_id": project_id,
        "language": language,
        "audio": _build_audio_manifest(transcript_payload),
        "content_start_ms": tokens[0]["start_ms"] if tokens else 0,
        "content_end_ms": tokens[-1]["end_ms"] if tokens else 0,
        "stats": _build_sync_stats(tokens=tokens, gaps=gaps, match_payload=match_payload),
        "tokens": tokens,
        "gaps": gaps,
    }


def build_sync_artifact(
    *,
    session: Session,
    project_id: str,
    job_id: str,
    object_store: ObjectStore,
) -> SyncArtifact:
    project = get_project_or_404(session=session, project_id=project_id)
    job = get_job_or_404(session=session, project_id=project_id, job_id=job_id)
    transcript_artifact = get_transcript_artifact_or_404(
        session=session,
        project_id=project_id,
        job_id=job_id,
    )
    match_artifact = get_match_artifact_or_404(
        session=session,
        project_id=project_id,
        job_id=job_id,
    )

    transcript_payload = object_store.read_json(transcript_artifact.storage_path)
    match_payload = object_store.read_json(match_artifact.storage_path)
    sync_payload = build_sync_payload(
        project_id=project_id,
        language=project.language,
        transcript_payload=transcript_payload,
        match_payload=match_payload,
    )

    artifact_id = str(uuid4())
    storage_path, size_bytes = object_store.write_json(
        f"projects/{project_id}/artifacts/sync/{artifact_id}.json",
        sync_payload,
    )

    artifact = SyncArtifact(
        id=artifact_id,
        project_id=project_id,
        job_id=job_id,
        version="1.0",
        status="generated",
        download_url=None,
        inline_payload=sync_payload,
        storage_path=storage_path,
        size_bytes=size_bytes,
    )
    session.add(artifact)

    job.progress_stage = "sync_export"
    job.progress_percent = 90
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
