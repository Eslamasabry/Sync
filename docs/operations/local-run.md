# Local Run Guide

## Goal

Boot the local stack, create a project with an EPUB and audio file, and run the Flutter reader against it.

## 1. Scripted Path

Static smoke test:

```bash
cd /home/eslam/Storage/Code/Sync
make local-full-smoke
```

WhisperX-based run:

```bash
cd /home/eslam/Storage/Code/Sync
make local-full-smoke-whisperx
```

The scripted flow uses:

- [bootstrap.sh](/home/eslam/Storage/Code/Sync/scripts/local/bootstrap.sh) to prepare infra and dependencies
- [start_services.sh](/home/eslam/Storage/Code/Sync/scripts/local/start_services.sh) to launch the API and worker
- [run_smoke.sh](/home/eslam/Storage/Code/Sync/scripts/local/run_smoke.sh) to create a project, upload generated sample files, and run alignment
- [stop_services.sh](/home/eslam/Storage/Code/Sync/scripts/local/stop_services.sh) to stop the background API and worker

## 2. Manual Path

### Start Infrastructure

```bash
cd /home/eslam/Storage/Code/Sync
cp backend/.env.example backend/.env
make dev-up
make backend-install-alignment
make flutter-get
```

### Run the Backend

In one terminal:

```bash
cd /home/eslam/Storage/Code/Sync
make backend-run
```

Optional worker in another terminal:

```bash
cd /home/eslam/Storage/Code/Sync
make worker-run
```

### Create a Project

```bash
curl -X POST http://localhost:8000/v1/projects \
  -H 'content-type: application/json' \
  -d '{"title":"Local Demo","language":"en"}'
```

Save the returned `project_id`.

### Upload the EPUB

```bash
curl -X POST http://localhost:8000/v1/projects/<project-id>/assets/upload \
  -F kind=epub \
  -F file=@/absolute/path/to/book.epub
```

### Upload the Audio

```bash
curl -X POST http://localhost:8000/v1/projects/<project-id>/assets/upload \
  -F kind=audio \
  -F file=@/absolute/path/to/book.mp3
```

You can use `.wav` during local testing as well.

### Create an Alignment Job

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

### Run the Flutter App

```bash
cd /home/eslam/Storage/Code/Sync
make flutter-run PROJECT_ID=<project-id>
```

If you need a different backend host:

```bash
make flutter-run API_BASE_URL=http://localhost:8000/v1 PROJECT_ID=<project-id>
```

## Notes

- If the backend is unavailable, the Flutter app falls back to the built-in demo content.
- Real audio playback is used only when the backend project loads and the sync artifact references uploaded audio assets.
- The current backend keeps artifacts in the local filesystem under `backend/artifacts` unless you override `ALIGNMENT_WORKDIR`.
- WhisperX is the proper alignment path, but it pulls a large PyTorch stack and runs best on a machine with a supported GPU. The static provider is there for quick smoke validation only.
