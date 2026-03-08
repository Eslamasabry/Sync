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
- tests: `pytest`

## Local Run

```bash
cp backend/.env.example backend/.env
make dev-up
make backend-install
make backend-run
```

Useful commands from repo root:

```bash
make backend-test
make backend-lint
make backend-typecheck
make worker-run
```

Implementation must follow:

- [docs/architecture/foundations.md](/home/eslam/Storage/Code/Sync/docs/architecture/foundations.md)
- [docs/contracts/api.md](/home/eslam/Storage/Code/Sync/docs/contracts/api.md)
- [docs/contracts/sync-format.md](/home/eslam/Storage/Code/Sync/docs/contracts/sync-format.md)
