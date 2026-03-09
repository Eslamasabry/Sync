# API and Realtime Contract

## Principles

- Public API version prefix: `/v1`
- JSON request and response bodies
- UUIDs for public identifiers
- Long-running work uses job resources, not blocking endpoints

## Runtime Middleware

The backend runtime supports deployment-facing middleware configuration through environment variables:

- `ENABLE_GZIP` and `GZIP_MINIMUM_SIZE` control response compression.
- `CORS_ALLOW_ORIGINS`, `CORS_ALLOW_ORIGIN_REGEX`, `CORS_ALLOW_METHODS`, `CORS_ALLOW_HEADERS`, and `CORS_ALLOW_CREDENTIALS` control browser cross-origin access.
- `TRUSTED_HOSTS` enables host-header allowlisting for reverse-proxied or public deployments.

Safe defaults:

- GZip is enabled by default.
- CORS is disabled by default until origins are configured.
- trusted hosts are disabled by default until explicit hostnames or IPs are configured.

## Resource Model

### Main resources

- `Project`
- `Asset`
- `AlignmentJob`
- `SyncArtifact`

## REST Endpoints

### `GET /v1/health`

Pure liveness probe for process-level uptime. This endpoint must stay cheap and should not perform dependency I/O.

Response:

```json
{
  "status": "ok",
  "probe": "liveness",
  "service": "sync-backend",
  "environment": "dev",
  "checked_at": "2026-03-09T00:00:00Z"
}
```

### `GET /v1/ready`

Readiness probe for automation and deploy orchestration. Returns dependency-level results with latency and machine-readable failure metadata.

Response when ready:

```json
{
  "status": "ready",
  "probe": "readiness",
  "service": "sync-backend",
  "environment": "dev",
  "checked_at": "2026-03-09T00:00:00Z",
  "summary": {
    "ready_checks": 3,
    "skipped_checks": 0,
    "failed_checks": 0
  },
  "checks": {
    "database": {
      "status": "ok",
      "critical": true,
      "latency_ms": 4.211
    },
    "redis": {
      "status": "ok",
      "critical": true,
      "latency_ms": 1.102
    },
    "object_store": {
      "status": "ok",
      "critical": true,
      "latency_ms": 0.321
    }
  }
}
```

Response when degraded:

```json
{
  "status": "degraded",
  "probe": "readiness",
  "service": "sync-backend",
  "environment": "dev",
  "checked_at": "2026-03-09T00:00:00Z",
  "summary": {
    "ready_checks": 2,
    "skipped_checks": 0,
    "failed_checks": 1
  },
  "checks": {
    "database": {
      "status": "error",
      "critical": true,
      "latency_ms": 0.882,
      "error_type": "OperationalError",
      "detail": "connection refused"
    }
  }
}
```

Notes:

- `200 OK` means all critical checks passed or were intentionally skipped.
- `503 Service Unavailable` means at least one critical dependency check failed.
- `status: skipped` is reserved for environments where a dependency is intentionally not exercised, such as Redis in backend tests.
- `latency_ms` is rounded and intended for automation/debugging, not billing-grade metrics.

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

### `POST /v1/projects/{project_id}/assets/upload`

Uploads and registers an asset in one request.

Request:

- content type: `multipart/form-data`
- fields:
  - `kind`: `epub` or `audio`
  - `file`: uploaded file blob

Response:

```json
{
  "asset_id": "uuid",
  "upload_mode": "multipart",
  "status": "uploaded"
}
```

### `GET /v1/projects/{project_id}/assets/{asset_id}/content`

Streams the raw uploaded asset content for local development and playback.

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

Notes:

- In the current backend, creating a job also dispatches background processing immediately when `APP_ENV != test`.
- The backend uses the project `language` as a hint for speech transcription when the underlying transcriber supports it.

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

Response shape in dev mode:

```json
{
  "project_id": "uuid",
  "job_id": "uuid",
  "version": "1.0",
  "status": "generated",
  "download_url": null,
  "inline_payload": {
    "book_id": "uuid",
    "audio": [],
    "tokens": [],
    "gaps": []
  }
}
```

Notes:

- `download_url` points to `GET /v1/projects/{project_id}/sync/content` when the artifact is stored as a file instead of returned inline.
- `inline_payload` is primarily a development convenience. Clients should be prepared to fetch `download_url` instead of assuming the full sync artifact is embedded in the metadata response.

### `GET /v1/projects/{project_id}/jobs/{job_id}/transcript`

Returns the latest transcript artifact generated for the job.

Response shape:

```json
{
  "project_id": "uuid",
  "job_id": "uuid",
  "version": "1.0",
  "status": "generated",
  "download_url": "http://localhost:8000/v1/projects/uuid/jobs/uuid/transcript/content",
  "language": "en",
  "segment_count": 12,
  "word_count": 834,
  "payload": {
    "segments": []
  }
}
```

Notes:

- `download_url` always points to the artifact content route even when `payload` is embedded for convenience.

### `GET /v1/projects/{project_id}/jobs/{job_id}/matches`

Returns the latest transcript-to-reader-model match artifact for the job.

Response shape:

```json
{
  "project_id": "uuid",
  "job_id": "uuid",
  "version": "1.0",
  "status": "generated",
  "download_url": "http://localhost:8000/v1/projects/uuid/jobs/uuid/matches/content",
  "match_count": 788,
  "gap_count": 46,
  "average_confidence": 0.9834,
  "payload": {
    "matches": [],
    "gaps": []
  }
}
```

### `GET /v1/projects/{project_id}/reader-model`

Returns the canonical backend-generated reader model for the project.

Response shape:

```json
{
  "project_id": "uuid",
  "asset_id": "uuid",
  "version": "1.0",
  "status": "generated",
  "download_url": "http://localhost:8000/v1/projects/uuid/reader-model/content",
  "model": {
    "title": "Moby-Dick",
    "sections": []
  }
}
```

### Artifact Content Endpoints

- `GET /v1/projects/{project_id}/sync/content`
- `GET /v1/projects/{project_id}/reader-model/content`
- `GET /v1/projects/{project_id}/jobs/{job_id}/transcript/content`
- `GET /v1/projects/{project_id}/jobs/{job_id}/matches/content`

These routes stream the persisted JSON artifact files with `application/json` content type. They exist so clients and operators can fetch the canonical stored artifact without depending on inline metadata payloads.

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
