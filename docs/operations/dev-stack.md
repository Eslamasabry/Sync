# Local Development Stack

## Local Services

The repo supports two local infrastructure modes:

- host services: PostgreSQL and Redis installed directly on the machine
- Docker Compose: PostgreSQL, Redis, and MinIO in containers

Use host services when you want a lighter loop and do not need MinIO locally.
Use `OBJECT_STORE_MODE=s3` when you want the smoke path to exercise MinIO or another S3-compatible blob store instead of the default filesystem-backed blobs.

Use local containers for:

- PostgreSQL
- Redis
- MinIO

Run API, worker, and Flutter app directly during development unless containerized testing is needed.

## External Dependencies

- `ffmpeg`
- Python 3.12 toolchain
- Flutter SDK

Notes:

- MP3 and other compressed audio preprocessing requires `ffmpeg`.
- If host `ffmpeg` is missing, installing the backend `alignment` extra provides a vendored binary through `imageio-ffmpeg`.
- If host `ffprobe` is missing, compressed-audio duration can still be read through `mutagen`.
- WAV segmentation works without `ffmpeg`, which is how the automated tests exercise the transcription pipeline.

## Standard Local Stack

- `compose.yaml` runs PostgreSQL, Redis, and MinIO
- `minio-init` creates the default `sync-dev` bucket
- backend code runs directly from `backend/`
- current backend implementation stores blobs in the local filesystem under `ALIGNMENT_WORKDIR/object_store`
- MinIO is provisioned now so a later S3-compatible adapter can switch in without changing local infrastructure
- `OBJECT_STORE_MODE=s3` is now supported for durable S3-compatible blob storage. In that mode, API asset and artifact downloads stream from object storage while alignment stages materialize temporary local files only for processing tools like `ffmpeg`.

## Host Services Stack

Host mode expects:

- PostgreSQL on `localhost:5432`
- Redis on `localhost:6379`
- backend code running directly from `backend/`
- artifacts still stored in the local filesystem under `ALIGNMENT_WORKDIR/object_store`

The local scripts can target host services directly:

```bash
make local-bootstrap-host
make local-start
make local-smoke
```

If PostgreSQL and Redis run on the host but you still want object-store coverage, start MinIO separately on `localhost:9000` and use:

```bash
make local-bootstrap-s3
make local-start
make local-smoke
```

For the lightest possible development loop, the local scripts can also target SQLite plus inline execution:

```bash
make local-bootstrap-lite
make local-start-lite
make local-smoke
```

## Bootstrap

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

Optional worker:

```bash
make worker-run
```

Skip the worker entirely when `JOB_EXECUTION_MODE=inline`.

Host-services alternative:

```bash
cp backend/.env.example backend/.env
make local-bootstrap-host
make local-start
```

## Environment Variables

Backend baseline:

- `APP_ENV`
- `ENABLE_GZIP`
- `GZIP_MINIMUM_SIZE`
- `CORS_ALLOW_ORIGINS`
- `CORS_ALLOW_ORIGIN_REGEX`
- `CORS_ALLOW_METHODS`
- `CORS_ALLOW_HEADERS`
- `CORS_ALLOW_CREDENTIALS`
- `TRUSTED_HOSTS`
- `DATABASE_URL`
- `REDIS_URL`
- `JOB_EXECUTION_MODE`
- `S3_ENDPOINT_URL`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `S3_BUCKET`
- `ALIGNMENT_WORKDIR`
- `OBJECT_STORE_MODE`
- `FFMPEG_BIN`
- `FFPROBE_BIN`
- `AUDIO_CHUNK_DURATION_MS`
- `TRANSCRIBER_PROVIDER`
- `WHISPER_MODEL_NAME`

Defaults are provided in [backend/.env.example](/home/eslam/Storage/Code/Sync/backend/.env.example).

Runtime notes:

- `ENABLE_GZIP=true` is safe for most deployments and is enabled by default.
- `CORS_ALLOW_ORIGINS` accepts a comma-separated list such as `https://reader.example.com,https://app.example.com`.
- `CORS_ALLOW_ORIGIN_REGEX` is useful for preview or wildcard-style subdomain deployments.
- If neither CORS variable is set, the backend does not permit browser cross-origin calls.
- `TRUSTED_HOSTS` accepts a comma-separated list of allowed hostnames or IPs and is recommended behind a reverse proxy.
- `JOB_EXECUTION_MODE=celery` keeps the default worker-based path. `JOB_EXECUTION_MODE=inline` lets the API execute jobs in-process and allows Redis readiness to be skipped.
- `DATABASE_URL=sqlite+pysqlite:///...` is supported for single-host or lightweight local runs.
- `OBJECT_STORE_MODE=filesystem` keeps local blobs under `ALIGNMENT_WORKDIR/object_store`. `OBJECT_STORE_MODE=s3` uses `S3_ENDPOINT_URL`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, and `S3_BUCKET` for durable blob storage.
- `make local-full-smoke-s3` validates the reader-model and sync `download_url` routes in addition to the metadata routes, so the S3-backed artifact path is exercised end to end.

## Local Endpoints

- API: `http://localhost:8000`
- PostgreSQL: `localhost:5432`
- Redis: `localhost:6379`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`

## Dev Rule

Intermediate artifacts should be preserved in local development by default because they are required for debugging alignment quality.

## Self-Hosted Release

For a host-based open-source deployment instead of a local dev stack, use the templates and operator guide in:

- [docs/operations/self-hosted.md](/home/eslam/Storage/Code/Sync/docs/operations/self-hosted.md)
- [deploy/systemd/sync-api.service](/home/eslam/Storage/Code/Sync/deploy/systemd/sync-api.service)
- [deploy/systemd/sync-worker.service](/home/eslam/Storage/Code/Sync/deploy/systemd/sync-worker.service)
- [deploy/nginx/sync.conf](/home/eslam/Storage/Code/Sync/deploy/nginx/sync.conf)
