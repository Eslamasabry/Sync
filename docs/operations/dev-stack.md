# Local Development Stack

## Local Services

Use local containers for:

- PostgreSQL
- Redis
- MinIO

Run API, worker, and Flutter app directly during development unless containerized testing is needed.

## External Dependencies

- `ffmpeg`
- Python 3.12 toolchain
- Flutter SDK

## Standard Local Stack

- `compose.yaml` runs PostgreSQL, Redis, and MinIO
- `minio-init` creates the default `sync-dev` bucket
- backend code runs directly from `backend/`

## Bootstrap

```bash
cp backend/.env.example backend/.env
make dev-up
make backend-install
make backend-run
```

Optional worker:

```bash
make worker-run
```

## Environment Variables

Backend baseline:

- `APP_ENV`
- `DATABASE_URL`
- `REDIS_URL`
- `S3_ENDPOINT_URL`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `S3_BUCKET`
- `ALIGNMENT_WORKDIR`

Defaults are provided in [backend/.env.example](/home/eslam/Storage/Code/Sync/backend/.env.example).

## Local Endpoints

- API: `http://localhost:8000`
- PostgreSQL: `localhost:5432`
- Redis: `localhost:6379`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`

## Dev Rule

Intermediate artifacts should be preserved in local development by default because they are required for debugging alignment quality.
