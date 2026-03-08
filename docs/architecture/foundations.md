# Architecture Foundations

## Scope

This document locks the baseline technical decisions for MVP so implementation can start without re-litigating the basics every week.

## System Shape

```text
Flutter Reader
   |  REST + WebSocket
   v
FastAPI API
   |  creates jobs, serves metadata, emits events
   v
Redis + Celery
   |  schedules long-running work
   v
Alignment Workers
   |  reads/writes artifacts
   v
Postgres + Object Storage
```

## Decision Summary

### 1. Canonical Reading Model

The backend will parse EPUB input into a canonical reading model:

- book
- sections
- paragraphs
- tokens
- stable token locations

The Flutter app renders this model directly. This avoids layout mismatch between EPUB HTML and aligned tokens.

### 2. Transport Strategy

- REST handles uploads, project creation, project reads, artifact downloads, and seekable metadata.
- WebSockets handle job progress and live worker events.

Reason:

- uploads and downloads need standard HTTP semantics
- job progress needs low-latency push updates

### 3. Background Processing

Alignment runs as a job pipeline because even short books can take minutes and long books can take much longer. The API must stay thin and non-blocking.

### 4. Storage Split

- Postgres stores projects, jobs, statuses, and artifact metadata.
- Object storage stores raw EPUB, audio, normalized text artifacts, transcript chunks, and final sync output.

### 5. Alignment Engine Strategy

The alignment worker exposes stable internal interfaces:

- `Transcriber`
- `TextMatcher`
- `ForcedAligner`
- `SyncExporter`

This keeps WhisperX, MFA, or later replacements swappable.

## Core Backend Components

### API

Responsibilities:

- project creation
- upload orchestration
- job creation and cancellation
- metadata reads
- WebSocket event fan-out

### Workers

Responsibilities:

- audio pre-processing
- transcription
- text matching
- forced alignment
- sync export
- artifact persistence

### Storage Layer

Responsibilities:

- durable metadata
- content-addressable or UUID-based artifact storage
- resumable access to intermediate outputs

## Job Lifecycle

States:

- `created`
- `uploading`
- `queued`
- `running`
- `needs_review`
- `completed`
- `failed`
- `cancelled`

Notes:

- `needs_review` is used when output exists but mismatch confidence is low.
- `completed` means sync output is valid and downloadable.

## MVP Pipeline

1. Ingest EPUB and MP3 assets.
2. Normalize EPUB into token stream and section map.
3. Convert and segment audio with ffmpeg.
4. Run transcription.
5. Match transcript windows to book windows.
6. Run forced alignment for matched spans.
7. Export `sync.json`.
8. Publish completion event.

## Performance Baselines

- Target audio length per project: up to 20 hours
- End-to-end processing: under 10x real-time audio length
- Highlight latency in client: under 50 ms

## Explicit Rejections

- No chapter-bound pipeline assumptions
- No WebView-dependent highlighting in MVP
- No synchronous alignment requests
- No direct worker-to-client connections
