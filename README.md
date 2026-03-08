# Open-Source Word-Level Audiobook EPUB Sync

An open-source system that aligns an EPUB with a matching audiobook and highlights text word by word during playback.

## Status

This repository is in foundation setup. The goal of the current phase is to lock the baseline decisions before implementation starts.

## Product Goal

- Input: EPUB + MP3 audiobook
- Output: word-level timing data + synced reading experience
- Platforms: Python backend and Flutter client

## Core Principles

- Contracts first: keep API, sync JSON, and reader data stable.
- Deterministic rendering: the reader must highlight the same token model the backend aligned.
- Async by default: alignment is a long-running job, not a request-response action.
- Offline matters: completed projects must work without network access.
- Mismatch tolerance matters more than perfect happy-path demos.

## Chosen Baseline

- Backend API: FastAPI
- Background jobs: Celery + Redis
- Metadata DB: PostgreSQL
- File storage: S3-compatible object storage, with MinIO for local development
- Realtime job updates: WebSockets
- Speech stack: WhisperX-based transcription, forced alignment behind an adapter
- Flutter state management: Riverpod
- Audio playback: just_audio
- API schema format: JSON over REST, versioned under `/v1`

## Repo Layout

```text
backend/
  api/
  alignment/
  workers/
  tests/
flutter_app/
  lib/
  test/
docs/
  architecture/
  contracts/
  design/
  engineering/
  operations/
```

## Source of Truth

- Product scope: [PRD-open-source-word-level-audiobook-epub-sync.md](/home/eslam/Storage/Code/Sync/PRD-open-source-word-level-audiobook-epub-sync.md)
- Epic backlog: [docs/product/epics.md](/home/eslam/Storage/Code/Sync/docs/product/epics.md)
- Agent and contribution rules: [AGENTS.md](/home/eslam/Storage/Code/Sync/AGENTS.md)
- Architecture baseline: [docs/architecture/foundations.md](/home/eslam/Storage/Code/Sync/docs/architecture/foundations.md)
- Flutter reader decision: [docs/architecture/flutter-reader-decision.md](/home/eslam/Storage/Code/Sync/docs/architecture/flutter-reader-decision.md)
- API and realtime contracts: [docs/contracts/api.md](/home/eslam/Storage/Code/Sync/docs/contracts/api.md)
- Reader document contract: [docs/contracts/reader-model.md](/home/eslam/Storage/Code/Sync/docs/contracts/reader-model.md)
- Sync artifact contract: [docs/contracts/sync-format.md](/home/eslam/Storage/Code/Sync/docs/contracts/sync-format.md)
- UI system: [docs/design/ui-theme.md](/home/eslam/Storage/Code/Sync/docs/design/ui-theme.md)
- Engineering standards: [docs/engineering/standards.md](/home/eslam/Storage/Code/Sync/docs/engineering/standards.md)
- Local dev stack: [docs/operations/dev-stack.md](/home/eslam/Storage/Code/Sync/docs/operations/dev-stack.md)
- Local run guide: [docs/operations/local-run.md](/home/eslam/Storage/Code/Sync/docs/operations/local-run.md)

## First Build Targets

1. Parse EPUB into a canonical token stream with stable locations.
2. Ingest audiobook files and create alignment jobs.
3. Produce a first version of `sync.json`.
4. Render aligned text in Flutter without a WebView.
5. Stream job progress over WebSockets.
