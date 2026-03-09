# Backend

Planned modules:

- `api/`: FastAPI routes, DTOs, and service wiring
- `alignment/`: normalization, matching, alignment adapters, and export
- `workers/`: Celery tasks and job orchestration
- `tests/`: unit and integration coverage

## Current Skeleton

- Python project manifest: `pyproject.toml`
- app package: `src/sync_backend`
- FastAPI entrypoint: `sync_backend.main:app`
- health endpoint: `GET /v1/health`
- Celery bootstrap: `sync_backend.workers.celery_app`
- transcript worker task: `sync_backend.workers.transcription:transcribe_alignment_job_task`
- end-to-end alignment task: `sync_backend.workers.pipeline:run_alignment_job_task`
- tests: `pytest`

## Local Run

Fastest scripted path from the repo root:

```bash
make local-full-smoke
make local-full-smoke-lite
make local-full-smoke-s3
make local-full-smoke-whisperx
```

Manual path:

```bash
cp backend/.env.example backend/.env
make dev-up
make backend-install
make backend-run
```

Optional alignment dependencies:

```bash
cd backend
.venv/bin/pip install -e '.[alignment,dev]'
```

Notes:

- `imageio-ffmpeg` provides a vendored `ffmpeg` binary when the host machine does not have one installed.
- `mutagen` is used as a duration-probe fallback when `ffprobe` is unavailable.
- `torchcodec` is pinned to the `0.7.x` line because `whisperx` currently installs with `torch 2.8.x`, and newer `torchcodec` releases emit runtime loader warnings with that stack.
- `whisperx` stays in the optional `alignment` extra because it pulls a large PyTorch stack.
- `OBJECT_STORE_MODE=filesystem` remains the local default. `OBJECT_STORE_MODE=s3` now works for durable S3-compatible storage, including streamed artifact downloads and temporary local materialization for EPUB/audio processing.
- `make local-full-smoke-s3` uses that mode and verifies the artifact `download_url` content routes during the smoke run.
- Runtime middleware is deployment-configurable through env vars:
  - `ENABLE_GZIP` and `GZIP_MINIMUM_SIZE`
  - `CORS_ALLOW_ORIGINS`, `CORS_ALLOW_ORIGIN_REGEX`, `CORS_ALLOW_METHODS`, `CORS_ALLOW_HEADERS`, `CORS_ALLOW_CREDENTIALS`
  - `TRUSTED_HOSTS`
- Blob storage is filesystem-backed by default, but `OBJECT_STORE_MODE=s3` now supports durable S3-compatible storage through `boto3` using the existing `S3_ENDPOINT_URL`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, and `S3_BUCKET` settings.
- CORS is off by default. That is intentional for safe local and server-side use. Enable it explicitly for Flutter web or other cross-origin clients.
- `TRUSTED_HOSTS` is also off by default. Set it in deployed environments to lock accepted `Host` headers to your real domains or LAN IPs.

Useful commands from repo root:

```bash
make backend-test
make backend-lint
make backend-typecheck
make worker-run
```

Lightweight open-source mode:

- `JOB_EXECUTION_MODE=inline` lets the API execute alignment jobs in-process through FastAPI background tasks.
- SQLite works out of the box through `DATABASE_URL=sqlite+pysqlite:///...`.
- `make local-bootstrap-lite` and `make local-start-lite` configure that mode automatically and avoid the Celery worker/Redis requirement.

Implementation must follow:

- [docs/architecture/foundations.md](/home/eslam/Storage/Code/Sync/docs/architecture/foundations.md)
- [docs/contracts/api.md](/home/eslam/Storage/Code/Sync/docs/contracts/api.md)
- [docs/contracts/sync-format.md](/home/eslam/Storage/Code/Sync/docs/contracts/sync-format.md)
