# API and Realtime Contract

## Principles

- Public API version prefix: `/v1`
- JSON request and response bodies
- UUIDs for public identifiers
- Long-running work uses job resources, not blocking endpoints

## Resource Model

### Main resources

- `Project`
- `Asset`
- `AlignmentJob`
- `SyncArtifact`

## REST Endpoints

### `POST /v1/projects`

Creates a project shell.

Request:

```json
{
  "title": "Moby-Dick",
  "language": "en"
}
```

Response:

```json
{
  "project_id": "uuid",
  "status": "created",
  "created_at": "2026-03-09T00:00:00Z"
}
```

### `POST /v1/projects/{project_id}/assets`

Registers an uploaded asset.

Request:

```json
{
  "kind": "epub",
  "filename": "moby-dick.epub",
  "content_type": "application/epub+zip"
}
```

Response:

```json
{
  "asset_id": "uuid",
  "upload_mode": "multipart",
  "status": "uploading"
}
```

Notes:

- MVP can use direct multipart upload through the API.
- Production can add presigned object-storage uploads later without changing the project model.

### `POST /v1/projects/{project_id}/jobs`

Creates an alignment job after required assets exist.

Request:

```json
{
  "job_type": "alignment",
  "audio_asset_ids": ["uuid"],
  "book_asset_id": "uuid"
}
```

Response:

```json
{
  "job_id": "uuid",
  "status": "queued"
}
```

### `GET /v1/projects/{project_id}`

Returns project metadata and latest job summary.

### `GET /v1/projects/{project_id}/jobs/{job_id}`

Returns detailed job status, progress, and artifact pointers.

Response shape:

```json
{
  "job_id": "uuid",
  "status": "running",
  "progress": {
    "stage": "transcription",
    "percent": 42
  },
  "quality": {
    "match_confidence": null,
    "mismatch_ranges": []
  }
}
```

### `GET /v1/projects/{project_id}/sync`

Returns sync artifact metadata and download URL or direct payload in dev mode.

### `POST /v1/projects/{project_id}/jobs/{job_id}/cancel`

Requests cancellation for a running or queued job.

## WebSocket

### Endpoint

`GET /v1/ws/projects/{project_id}`

Purpose:

- project-scoped job updates
- lightweight processing events
- completion and failure notifications

### Message envelope

```json
{
  "type": "job.progress",
  "project_id": "uuid",
  "job_id": "uuid",
  "timestamp": "2026-03-09T00:00:00Z",
  "payload": {}
}
```

### Event types

- `job.queued`
- `job.started`
- `job.progress`
- `job.needs_review`
- `job.completed`
- `job.failed`
- `job.cancelled`

### `job.progress` payload

```json
{
  "stage": "forced_alignment",
  "percent": 78,
  "message": "Aligning segment 18 of 23"
}
```

## Error Model

```json
{
  "error": {
    "code": "asset_missing",
    "message": "An EPUB asset is required before creating an alignment job",
    "details": {}
  }
}
```

Rules:

- `code` is stable and machine-readable.
- `message` is safe for UI display.
- `details` is optional and structured.

## Compatibility Rules

- New fields may be added.
- Existing required fields may not be renamed without `/v2`.
- WebSocket event `type` strings are contract-level identifiers and should remain stable.
