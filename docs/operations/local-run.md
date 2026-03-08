# Local Run Guide

## Goal

Boot the local stack, create a project with an EPUB and audio file, and run the Flutter reader against it.

## 1. Choose A Local Mode

There are two viable local setups:

- Docker-backed infra: easiest if you want the repo defaults exactly as written.
- Host-services infra: lighter if you already run `postgresql` and `redis-server` locally and want to avoid Docker during day-to-day work.

For the Flutter app, the important variable is always the backend base URL you pass through `SYNC_API_BASE_URL`.

## 2. Scripted Path

Static smoke test:

```bash
cd /home/eslam/Storage/Code/Sync
make local-full-smoke
```

Host-services smoke test:

```bash
cd /home/eslam/Storage/Code/Sync
make local-full-smoke-host
```

WhisperX-based run:

```bash
cd /home/eslam/Storage/Code/Sync
make local-full-smoke-whisperx
```

The scripted flow uses:

- [bootstrap.sh](/home/eslam/Storage/Code/Sync/scripts/local/bootstrap.sh) to prepare infra and dependencies
- [start_services.sh](/home/eslam/Storage/Code/Sync/scripts/local/start_services.sh) to launch the API and worker
- [status_services.sh](/home/eslam/Storage/Code/Sync/scripts/local/status_services.sh) to inspect PID and readiness state
- [run_smoke.sh](/home/eslam/Storage/Code/Sync/scripts/local/run_smoke.sh) to create a project, upload generated sample files, and run alignment
- [stop_services.sh](/home/eslam/Storage/Code/Sync/scripts/local/stop_services.sh) to stop the background API and worker

For a real public-domain quality pass instead of a synthetic smoke test, use [docs/operations/regression.md](/home/eslam/Storage/Code/Sync/docs/operations/regression.md).

The scripted path starts the backend on `127.0.0.1:8000`. That is fine for desktop and simulators, but not for a physical device on your LAN.

## 3. Manual Path

### Option A: Docker-Backed Infra

Start infrastructure:

```bash
cd /home/eslam/Storage/Code/Sync
cp backend/.env.example backend/.env
make dev-up
make backend-install-alignment
make flutter-get
```

### Option B: Host-Services Infra

Install and start host services:

```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib redis-server redis-tools ffmpeg
sudo systemctl enable --now postgresql redis-server
sudo -u postgres psql -c "CREATE USER sync WITH PASSWORD 'sync';" || true
sudo -u postgres psql -c "ALTER USER sync WITH PASSWORD 'sync';"
sudo -u postgres psql -c "CREATE DATABASE sync OWNER sync;" || true
```

Then prepare the repo:

```bash
cd /home/eslam/Storage/Code/Sync
cp backend/.env.example backend/.env
make local-bootstrap-host
```

Sanity-check infrastructure:

```bash
pg_isready -h localhost -p 5432
redis-cli ping
```

### Run The Backend

In one terminal:

```bash
cd /home/eslam/Storage/Code/Sync
make backend-run
```

The default `make backend-run` binds `127.0.0.1:8000`. Use that for desktop, Linux, macOS, Windows, and iOS simulator runs.

If you need the Flutter app to connect from a physical device on the same LAN, run the API directly instead:

```bash
cd /home/eslam/Storage/Code/Sync/backend
.venv/bin/uvicorn sync_backend.main:app --host 0.0.0.0 --port 8000 --reload
```

Run the worker in another terminal:

```bash
cd /home/eslam/Storage/Code/Sync
make worker-run
```

If you want the scripts to manage the background API and worker instead:

```bash
cd /home/eslam/Storage/Code/Sync
make local-start
make local-status
```

### Create A Project

```bash
curl -X POST http://localhost:8000/v1/projects \
  -H 'content-type: application/json' \
  -d '{"title":"Local Demo","language":"en"}'
```

Save the returned `project_id`.

### Upload The EPUB

```bash
curl -X POST http://localhost:8000/v1/projects/<project-id>/assets/upload \
  -F kind=epub \
  -F file=@/absolute/path/to/book.epub
```

### Upload The Audio

```bash
curl -X POST http://localhost:8000/v1/projects/<project-id>/assets/upload \
  -F kind=audio \
  -F file=@/absolute/path/to/book.mp3
```

You can use `.wav` during local testing as well.

### Create An Alignment Job

Fetch the project detail first so you can copy the uploaded asset ids:

```bash
curl http://localhost:8000/v1/projects/<project-id>
```

Then create the job:

```bash
curl -X POST http://localhost:8000/v1/projects/<project-id>/jobs \
  -H 'content-type: application/json' \
  -d '{
    "job_type":"alignment",
    "book_asset_id":"<epub-asset-id>",
    "audio_asset_ids":["<audio-asset-id>"]
  }'
```

### Check Generated Artifacts

```bash
curl http://localhost:8000/v1/projects/<project-id>/reader-model
curl http://localhost:8000/v1/projects/<project-id>/sync
curl http://localhost:8000/v1/projects/<project-id>/jobs/<job-id>
```

Audio files are streamed back to the client from:

```text
GET /v1/projects/{project_id}/assets/{asset_id}/content
```

### Run The Flutter App

Desktop or iOS simulator:

```bash
cd /home/eslam/Storage/Code/Sync
make flutter-run PROJECT_ID=<project-id>
```

Android emulator:

```bash
make flutter-run API_BASE_URL=http://10.0.2.2:8000/v1 PROJECT_ID=<project-id>
```

Physical device on the same LAN:

```bash
make flutter-run API_BASE_URL=http://<host-lan-ip>:8000/v1 PROJECT_ID=<project-id>
```

## 4. Production-Adjacent Notes

- For real deployments, prefer an `https://` API origin so the Flutter client upgrades its event channel to `wss://`.
- Your reverse proxy must forward `GET /v1/ws/projects/{project_id}` as a WebSocket upgrade, not plain HTTP only.
- Flutter web is not a first-class local path yet because the backend does not currently expose CORS middleware.
- Keep `ALIGNMENT_WORKDIR` on persistent storage if you care about artifacts surviving restarts.
- The scripted smoke run is good for validating the golden path, but the public-domain regression run is the better pre-release check.

## 5. Notes

- If the backend is unavailable, the Flutter app falls back to the built-in demo content.
- Real audio playback is used only when the backend project loads and the sync artifact references uploaded audio assets.
- The current backend keeps artifacts in the local filesystem under `backend/artifacts` unless you override `ALIGNMENT_WORKDIR`.
- WhisperX is the proper alignment path, but it pulls a large PyTorch stack and runs best on a machine with a supported GPU. The static provider is there for quick smoke validation only.
- `make local-full-smoke` now stops the background API and worker automatically unless you run the script with `--keep-running`.
- `make local-stop-host` stops the background API and worker and also stops host PostgreSQL and Redis.
- `make local-stop-docker` stops the background API and worker and also runs `docker compose down`.
