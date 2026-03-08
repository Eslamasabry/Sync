SHELL := /bin/bash

.PHONY: dev-up dev-down dev-logs backend-install backend-run backend-test backend-lint backend-typecheck worker-run

dev-up:
	docker compose up -d

dev-down:
	docker compose down

dev-logs:
	docker compose logs -f

backend-install:
	cd backend && python3 -m venv .venv && .venv/bin/pip install --upgrade pip && .venv/bin/pip install -e '.[dev]'

backend-run:
	cd backend && .venv/bin/uvicorn sync_backend.main:app --reload

backend-test:
	cd backend && .venv/bin/pytest

backend-lint:
	cd backend && .venv/bin/ruff check src tests

backend-typecheck:
	cd backend && .venv/bin/mypy src

worker-run:
	cd backend && .venv/bin/celery -A sync_backend.workers.celery_app:celery_app worker --loglevel=info
