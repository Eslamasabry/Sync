# Epic Backlog

## Purpose

This document defines the next 10 epics for MVP delivery. The order is intentional. Each epic is large enough to span multiple tasks or issues and small enough to produce a clear project outcome.

## Sequencing Rules

- Finish contracts and scaffolding before deep algorithm work.
- Build inspectable intermediate artifacts before chasing accuracy.
- Get one clean end-to-end path working before widening file and mismatch coverage.
- Keep the reader model and sync contract stable as early as possible.

## Epic 1: Backend Service Skeleton

### Goal

Create the runnable backend base so API, worker, config, logging, and package layout exist.

### Why now

Everything else depends on a stable app shell and shared configuration.

### Scope

- FastAPI application entrypoint
- settings and environment loading
- structured logging
- health endpoint
- package layout for `api`, `alignment`, and `workers`
- basic test harness

### Deliverables

- runnable API service
- Python project manifest
- baseline CI checks for backend formatting and tests

### Dependencies

- architecture baseline
- engineering standards

### Exit Criteria

- API starts locally
- config loads from environment
- health route responds
- basic backend tests run in CI

## Epic 2: Local Development Stack and Tooling

### Goal

Make local development repeatable for API, workers, database, queue, and object storage.

### Why now

Without a repeatable dev stack, every later epic will drift across environments.

### Scope

- `docker-compose` or equivalent for Postgres, Redis, and MinIO
- backend dev bootstrap commands
- local storage bucket initialization
- shared environment examples
- optional Makefile or task runner

### Deliverables

- one-command local infra startup
- documented setup flow
- working object storage and queue endpoints

### Dependencies

- Epic 1

### Exit Criteria

- a new contributor can boot infra locally
- API can connect to DB, Redis, and object storage
- workers can start against the same local stack

## Epic 3: Project, Asset, and Job API

### Goal

Implement the core REST and WebSocket contract for project creation, asset registration, and job lifecycle.

### Why now

The client and workers need stable orchestration before alignment logic is wired in.

### Scope

- `POST /v1/projects`
- `POST /v1/projects/{project_id}/assets`
- `POST /v1/projects/{project_id}/jobs`
- `GET /v1/projects/{project_id}`
- `GET /v1/projects/{project_id}/jobs/{job_id}`
- `POST /v1/projects/{project_id}/jobs/{job_id}/cancel`
- WebSocket endpoint for job events

### Deliverables

- Pydantic DTOs and validation
- persistence models for projects, assets, and jobs
- job state transitions
- WebSocket event publishing

### Dependencies

- Epic 1
- Epic 2

### Exit Criteria

- the contract in `docs/contracts/api.md` is implemented
- job state changes are queryable and stream over WebSockets
- invalid job creation paths return stable error codes

## Epic 4: Canonical EPUB Reader Model

### Goal

Turn EPUB input into the canonical backend-owned reader model that Flutter will render.

### Why now

Alignment and highlighting are only reliable if both backend and client point to the same token structure.

### Scope

- EPUB parsing
- spine traversal
- text extraction
- section and paragraph segmentation
- tokenization
- stable token indices
- optional CFI generation

### Deliverables

- reader model serializer
- normalization rules for display and matching
- fixture corpus of small EPUB samples

### Dependencies

- Epic 1
- Epic 3

### Exit Criteria

- EPUB files produce a stable reader model
- token indices remain stable across repeated runs
- malformed or noisy sections are handled safely

## Epic 5: Asset Uploads and Artifact Storage

### Goal

Support actual EPUB and audio asset ingestion plus artifact persistence across the pipeline.

### Why now

The pipeline cannot move beyond mock data without durable assets and intermediate outputs.

### Scope

- multipart upload handling
- asset metadata persistence
- object storage layout
- artifact path conventions
- download access for final outputs

### Deliverables

- EPUB and MP3 upload flow
- saved raw assets in object storage
- artifact registry metadata in Postgres

### Dependencies

- Epic 2
- Epic 3

### Exit Criteria

- a project can store source assets and reference them later
- artifact writes are traceable by project and job
- final sync output can be downloaded

## Epic 6: Audio Preprocessing and Transcription

### Goal

Convert raw audiobook inputs into normalized audio segments and transcript outputs with timestamps.

### Why now

This is the first hard dependency for real alignment output.

### Scope

- ffmpeg-based audio normalization
- support for single and multipart MP3 input
- chunking strategy for long audio
- WhisperX transcription adapter
- transcript artifact export with timestamps and confidence

### Deliverables

- transcript JSON artifact per project or segment
- audio preprocessing utilities
- timing and confidence capture

### Dependencies

- Epic 5

### Exit Criteria

- long-form audio can be segmented and processed
- transcript output is stored as an artifact
- failures surface useful stage-level error messages

## Epic 7: Transcript-to-Text Matching Engine

### Goal

Map transcript tokens onto book tokens with enough tolerance for real audiobook variation.

### Why now

This is the core step that turns transcription into book-aware alignment.

### Scope

- normalization parity between transcript and book tokens
- sliding window search
- fuzzy matching
- dynamic programming for best-path selection
- mismatch and skipped-range detection

### Deliverables

- matcher module behind a stable interface
- scored match spans
- mismatch diagnostics

### Dependencies

- Epic 4
- Epic 6

### Exit Criteria

- transcript spans map onto reader model locations
- known mismatch cases produce explicit gap output
- match confidence is available for later review and UI messaging

## Epic 8: Forced Alignment and Sync Export

### Goal

Refine matched spans into precise word timing and export the stable `sync.json` artifact.

### Why now

This creates the first real end product the reader can consume.

### Scope

- forced alignment adapter
- per-span timing refinement
- token time stitching across segments
- sync export matching `docs/contracts/sync-format.md`
- schema validation against `docs/contracts/sync.schema.json`

### Deliverables

- valid `sync.json`
- quality metadata and gap output
- export regression tests

### Dependencies

- Epic 7

### Exit Criteria

- exported sync artifacts validate against schema
- token timings are monotonic and usable by the client
- low-confidence and skipped ranges are preserved

## Epic 9: Flutter Reader MVP

### Goal

Build the first usable reading client that renders the reader model and responds to timing data.

### Why now

A synced backend is not enough; the user value appears only when the reader experience works.

### Scope

- app shell and routing
- project fetch and local cache
- reader model rendering
- token highlight engine
- bottom playback controls
- progress bar and seek
- paper and night themes

### Deliverables

- token-aware reader screen
- local theme system
- API client models

### Dependencies

- Epic 3
- Epic 4
- Epic 8

### Exit Criteria

- the app renders book text from the reader model
- active token highlight follows playback time
- seek and speed controls work in the reader

## Epic 10: End-to-End Reliability, Offline Mode, and Evaluation

### Goal

Harden the whole flow so the MVP works offline, reports quality clearly, and can be measured against target metrics.

### Why now

Without reliability and evaluation, the product will demo well but fail on real books.

### Scope

- offline sync and artifact caching
- job progress UI and failure handling
- golden-path fixture books and audio pairs
- alignment accuracy evaluation harness
- processing speed measurement
- regression suite for reader latency and sync quality

### Deliverables

- offline-capable MVP flow
- measurable evaluation dataset and scripts
- release readiness checklist

### Dependencies

- Epics 3 through 9

### Exit Criteria

- completed projects can run without network
- the team can measure alignment accuracy and processing time
- at least one full EPUB plus audiobook pair works end to end on the target stack

## Suggested Execution Path

### Wave 1

- Epic 1
- Epic 2
- Epic 3

### Wave 2

- Epic 4
- Epic 5
- Epic 6

### Wave 3

- Epic 7
- Epic 8
- Epic 9

### Wave 4

- Epic 10

## Notes

- If alignment quality becomes the main blocker, Epic 7 and Epic 8 should receive deeper sub-epics before widening UI scope.
- If contributor onboarding becomes urgent, split documentation and CI hardening out of Epic 1 and Epic 10 into a separate open-source operations epic.
