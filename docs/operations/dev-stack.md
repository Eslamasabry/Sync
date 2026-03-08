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

## Dev Rule

Intermediate artifacts should be preserved in local development by default because they are required for debugging alignment quality.
