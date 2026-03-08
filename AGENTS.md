# AGENTS.md

This file defines project-specific rules for agents and contributors working in this repository.

## Mission

Build an open-source system that aligns EPUB text with audiobook audio and drives a Flutter reader with word-level highlighting.

## Non-Negotiable Rules

1. Do not break the sync artifact contract without updating the contract docs first.
2. Do not treat raw EPUB HTML as the runtime reader source of truth in MVP.
3. Do not couple alignment logic to Flutter UI code or UI timing assumptions.
4. Do not use WebSockets for binary uploads or large data transfer.
5. Do not hide low-confidence matches; expose them in metadata.
6. Do not assume chapter boundaries exist or are trustworthy.
7. Do not add DRM support or cloud account features to MVP work.

## Architecture Guardrails

- REST is for create/read/update actions and asset lifecycle.
- WebSockets are only for live job state, progress, and lightweight events.
- Long-running work must run in background workers.
- Alignment engines must sit behind adapters so tools can be swapped.
- The reader should consume a normalized reading model, not parse EPUB ad hoc on-device.
- Storage is split into metadata in Postgres and blobs in object storage.

## Backend Rules

- Python version target: 3.12+
- Prefer typed Pydantic models at API boundaries.
- Keep alignment stages isolated:
  - ingest
  - normalize
  - transcribe
  - match
  - forced align
  - export
- Every stage must produce inspectable intermediate artifacts for debugging.
- Treat ffmpeg as an external dependency and keep shell invocations centralized.

## Flutter Rules

- Flutter should render normalized book sections and token spans from the backend model.
- Do not use a WebView-based EPUB renderer for MVP because deterministic token highlighting is the priority.
- Playback time is the only source of truth for active highlight state.
- UI must keep highlight updates cheap; avoid rebuilding the full page on every tick.

## Contract Rules

- API routes live under `/v1`.
- Sync times are stored in integer milliseconds.
- Public IDs are UUID strings.
- All timestamps in APIs are ISO 8601 UTC strings.
- New fields may be added in a backward-compatible way; existing fields should not silently change meaning.

## Testing Minimums

- Backend:
  - unit tests for token normalization, matching, and contract serialization
  - integration tests for job lifecycle and sync export
- Flutter:
  - widget tests for highlight behavior
  - playback state tests for seek and speed control
- Golden-path fixture pairs must be kept for regression testing.

## Documentation Rule

If code changes one of these, update docs in the same change:

- API shape
- sync schema
- repo structure
- theme tokens
- worker lifecycle
