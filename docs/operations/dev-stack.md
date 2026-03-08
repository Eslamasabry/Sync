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
- `OBJECT_STORE_MODE`
- `FFMPEG_BIN`
- `FFPROBE_BIN`
- `AUDIO_CHUNK_DURATION_MS`
- `TRANSCRIBER_PROVIDER`
- `WHISPER_MODEL_NAME`

Defaults are provided in [backend/.env.example](/home/eslam/Storage/Code/Sync/backend/.env.example).

## Local Endpoints

- API: `http://localhost:8000`
- PostgreSQL: `localhost:5432`
- Redis: `localhost:6379`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`

## Dev Rule

Intermediate artifacts should be preserved in local development by default because they are required for debugging alignment quality.
