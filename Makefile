SHELL := /bin/bash

API_BASE_URL ?= http://localhost:8000/v1
PROJECT_ID ?= demo-book
TRANSCRIBER_PROVIDER ?= static

.PHONY: dev-up dev-down dev-logs backend-install backend-install-alignment backend-run backend-test backend-lint backend-typecheck worker-run flutter-get flutter-run flutter-analyze flutter-test local-bootstrap local-bootstrap-host local-start local-status local-stop local-stop-host local-stop-docker local-smoke local-full-smoke local-full-smoke-host local-bootstrap-whisperx local-full-smoke-whisperx local-regression local-regression-gate local-regression-corpus local-regression-corpus-gate

dev-up:
	docker compose up -d

dev-down:
	docker compose down

dev-logs:
	docker compose logs -f

backend-install:
	cd backend && python3 -m venv .venv && .venv/bin/pip install --upgrade pip && .venv/bin/pip install -e '.[dev]'

backend-install-alignment:
	cd backend && python3 -m venv .venv && .venv/bin/pip install --upgrade pip && .venv/bin/pip install -e '.[alignment,dev]'

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

flutter-get:
	cd flutter_app && flutter pub get

flutter-run:
	cd flutter_app && flutter run --dart-define=SYNC_API_BASE_URL=$(API_BASE_URL) --dart-define=SYNC_PROJECT_ID=$(PROJECT_ID)

flutter-analyze:
	cd flutter_app && flutter analyze

flutter-test:
	cd flutter_app && flutter test

local-bootstrap:
	./scripts/local/bootstrap.sh --provider $(TRANSCRIBER_PROVIDER)

local-bootstrap-host:
	./scripts/local/bootstrap.sh --provider $(TRANSCRIBER_PROVIDER) --infra host

local-bootstrap-whisperx:
	./scripts/local/bootstrap.sh --provider whisperx

local-start:
	./scripts/local/start_services.sh

local-status:
	./scripts/local/status_services.sh

local-stop:
	./scripts/local/stop_services.sh

local-stop-host:
	./scripts/local/stop_services.sh --stop-host-infra

local-stop-docker:
	./scripts/local/stop_services.sh --stop-docker-infra

local-smoke:
	./scripts/local/run_smoke.sh --api-base-url $(API_BASE_URL) --provider $(TRANSCRIBER_PROVIDER)

local-full-smoke:
	./scripts/local/full_smoke.sh --provider $(TRANSCRIBER_PROVIDER)

local-full-smoke-host:
	./scripts/local/full_smoke.sh --provider $(TRANSCRIBER_PROVIDER) --infra host

local-full-smoke-whisperx:
	./scripts/local/full_smoke.sh --provider whisperx

local-regression:
	./scripts/local/run_public_domain_regression.sh --api-base-url $(API_BASE_URL)

local-regression-gate:
	./scripts/local/run_public_domain_regression.sh --api-base-url $(API_BASE_URL) --min-match-confidence 0.9 --min-coverage 0.85 --max-gap-ranges 80

local-regression-corpus:
	./scripts/local/run_regression_corpus.sh --api-base-url $(API_BASE_URL)

local-regression-corpus-gate:
	./scripts/local/run_regression_corpus.sh --api-base-url $(API_BASE_URL) --gate
