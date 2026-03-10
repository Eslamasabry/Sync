# Self-Hosted Deployment

This is the host-based deployment path for the open-source project. It assumes:

- Ubuntu or a similar Linux host
- PostgreSQL and Redis installed on the machine
- the repo deployed under `/opt/sync`
- the backend served behind `nginx`

For a single-host lightweight deployment, you can also run with:

- `DATABASE_URL=sqlite+pysqlite:////var/lib/sync/sync.db`
- `JOB_EXECUTION_MODE=inline`

That mode avoids PostgreSQL, Redis, and the separate worker service, but it trades away queue isolation and is better suited to small personal or demo deployments than multi-user production traffic.

## 1. Host Dependencies

```bash
sudo apt update
sudo apt install -y python3 python3-venv postgresql redis-server nginx ffmpeg
```

## 2. App User And Directories

```bash
sudo useradd --system --create-home --shell /bin/bash sync || true
sudo mkdir -p /opt/sync /var/lib/sync /etc/sync
sudo chown -R sync:sync /opt/sync /var/lib/sync
```

Optional token generation:

```bash
cd /opt/sync
./deploy/scripts/generate_api_auth_token.sh
```

## 3. Backend Install

```bash
sudo -u sync git clone https://github.com/Eslamasabry/Sync.git /opt/sync
cd /opt/sync/backend
sudo -u sync python3 -m venv .venv
sudo -u sync .venv/bin/pip install --upgrade pip setuptools wheel
sudo -u sync .venv/bin/pip install -e '.[alignment,dev]'
```

## 4. Backend Environment

Start from [backend.env.example](/home/eslam/Storage/Code/Sync/deploy/env/backend.env.example):

```bash
sudo cp /opt/sync/deploy/env/backend.env.example /etc/sync/backend.env
sudo chown root:sync /etc/sync/backend.env
sudo chmod 640 /etc/sync/backend.env
```

Edit:

- `DATABASE_URL`
- `REDIS_URL`
- `JOB_EXECUTION_MODE`
- `OBJECT_STORE_MODE`
- `S3_ENDPOINT_URL`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `S3_BUCKET`
- `CORS_ALLOW_ORIGINS`
- `TRUSTED_HOSTS`
- `API_AUTH_TOKEN`
- `ALIGNMENT_WORKDIR`

Use `OBJECT_STORE_MODE=filesystem` for the simplest host-only deployment. Use `OBJECT_STORE_MODE=s3` when you want durable blob storage in MinIO, AWS S3, or another S3-compatible service.
Set `API_AUTH_TOKEN` to a long random value when you want to protect uploads, downloads, jobs, and project-event WebSockets on a self-hosted instance. Leave it empty only for trusted local development or a deliberately open deployment.

## 5. PostgreSQL Bootstrap

```bash
sudo -u postgres psql -c "CREATE USER sync WITH PASSWORD 'change-me';" || true
sudo -u postgres psql -c "CREATE DATABASE sync OWNER sync;" || true
```

## 6. systemd Units

Install:

```bash
sudo cp /opt/sync/deploy/systemd/sync-api.service /etc/systemd/system/
sudo cp /opt/sync/deploy/systemd/sync-worker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sync-api sync-worker
```

If `JOB_EXECUTION_MODE=inline`, install and enable only `sync-api`. The worker service is not required in that mode.
If `OBJECT_STORE_MODE=s3`, keep `ALIGNMENT_WORKDIR` on local disk for temporary processing files while uploaded assets and generated artifacts persist in the configured bucket.

You can also copy the committed templates with:

```bash
cd /opt/sync
sudo ./deploy/scripts/install_self_hosted.sh
```

For SQLite + inline mode:

```bash
sudo ./deploy/scripts/install_self_hosted.sh --inline
```

## 7. nginx Reverse Proxy

Install:

```bash
sudo cp /opt/sync/deploy/nginx/sync.conf /etc/nginx/sites-available/sync.conf
sudo ln -sf /etc/nginx/sites-available/sync.conf /etc/nginx/sites-enabled/sync.conf
sudo nginx -t
sudo systemctl reload nginx
```

This sample is HTTP-only. Add TLS separately with your normal operator tooling.

## 8. Post-Deploy Checks

```bash
curl -f http://127.0.0.1:8000/v1/health
curl -f http://127.0.0.1:8000/v1/ready
systemctl status sync-api --no-pager
systemctl status sync-worker --no-pager
```

Scripted check:

```bash
cd /opt/sync
./deploy/scripts/post_deploy_check.sh --api-base-url http://127.0.0.1:8000/v1 --auth-token <token>
```

After the first successful alignment job on the host, verify artifact delivery directly:

```bash
curl -f -H "Authorization: Bearer <token>" http://127.0.0.1:8000/v1/projects/<project-id>/reader-model
curl -f -H "Authorization: Bearer <token>" http://127.0.0.1:8000/v1/projects/<project-id>/sync
curl -f -H "Authorization: Bearer <token>" -OJ http://127.0.0.1:8000/v1/projects/<project-id>/reader-model/content
curl -f -H "Authorization: Bearer <token>" -OJ http://127.0.0.1:8000/v1/projects/<project-id>/sync/content
curl -f -H "Authorization: Bearer <token>" -OJ http://127.0.0.1:8000/v1/projects/<project-id>/jobs/<job-id>/transcript/content
curl -f -H "Authorization: Bearer <token>" -OJ http://127.0.0.1:8000/v1/projects/<project-id>/jobs/<job-id>/matches/content
```

The metadata routes expose `download_url` fields for the stored JSON artifacts. That is the contract the Flutter client and external tooling should prefer instead of assuming inline artifact payloads are always present.

## 9. Release Validation

After deployment, run a real regression gate from the host:

```bash
cd /opt/sync
./scripts/local/run_regression_corpus.sh --api-base-url http://127.0.0.1:8000/v1 --gate
```

## 10. Railway Deployment

For a small self-hosted cloud deployment, Railway can run the API in inline mode with:

- SQLite on a mounted volume
- filesystem object storage on that same mounted volume
- `JOB_EXECUTION_MODE=inline`

This is the fastest hosted path for personal use, demos, and low-concurrency deployments. It avoids the separate worker service, but it is not the final scaling shape for heavier public traffic.

Recommended Railway service settings:

- service root: `backend`
- builder: `Dockerfile`
- volume mount: `/data`
- public domain enabled

Recommended environment:

```env
APP_ENV=production
LOG_LEVEL=INFO
JOB_EXECUTION_MODE=inline
DATABASE_URL=sqlite+pysqlite:////data/sync.db
OBJECT_STORE_MODE=filesystem
ALIGNMENT_WORKDIR=/data
TRANSCRIBER_PROVIDER=whisperx
WHISPER_MODEL_NAME=base
FFMPEG_BIN=ffmpeg
FFPROBE_BIN=ffprobe
ENABLE_GZIP=true
API_AUTH_TOKEN=<long-random-token>
```

If the Flutter app or web client will talk to Railway directly, also set either:

- `CORS_ALLOW_ORIGINS=https://your-app-origin.example`
- or `CORS_ALLOW_ORIGIN_REGEX=...`

After the first successful Railway deployment, verify:

```bash
curl -f https://<your-railway-domain>/v1/health
curl -f https://<your-railway-domain>/v1/ready
```

Use the generated Railway domain as the Flutter runtime `API base URL`, for example:

```text
https://<your-railway-domain>/v1
```
