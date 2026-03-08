# Multi-Agent Workstream Plan

## Goal

Parallelize the next production-hardening phase across clearly owned backend and frontend slices with minimal merge conflict risk.

## Backend Workstreams

### B1: API Runtime Health

- Owner files:
  - `backend/src/sync_backend/api/routes/health.py`
  - `backend/tests/test_health.py`
  - `docs/contracts/api.md`
- Goal:
  - harden runtime health and readiness semantics
  - expose dependency-level status cleanly for production automation
- Non-goals:
  - no alignment-pipeline changes
  - no Flutter changes

### B2: Transcription Runtime

- Owner files:
  - `backend/src/sync_backend/alignment/transcription.py`
  - `backend/src/sync_backend/alignment/transcription_pipeline.py`
  - `backend/tests/test_transcription_pipeline.py`
- Goal:
  - improve WhisperX runtime behavior, language handling, and long-job progress
- Non-goals:
  - no API contract changes
  - no Flutter changes

### B3: Matching and Sync Quality

- Owner files:
  - `backend/src/sync_backend/alignment/matching.py`
  - `backend/src/sync_backend/alignment/sync_export.py`
  - `backend/tests/test_matching.py`
  - `docs/contracts/sync-format.md`
- Goal:
  - improve transcript-to-book matching quality and sync artifact semantics
- Non-goals:
  - no queue or deployment changes

### B4: Project/Job API Surface

- Owner files:
  - `backend/src/sync_backend/api/routes/projects.py`
  - `backend/src/sync_backend/api/schemas.py`
  - `backend/tests/test_projects_api.py`
- Goal:
  - harden job and artifact API responses for production clients
- Non-goals:
  - no WhisperX runtime work

### B5: Ops and Regression Tooling

- Owner files:
  - `scripts/local/`
  - `docs/operations/`
  - `Makefile`
  - `README.md`
- Goal:
  - improve reproducible local/prod-adjacent operational workflows and regression tooling
- Non-goals:
  - no backend business-logic changes

## Frontend Workstreams

### F1: Sync Domain Models

- Owner files:
  - `flutter_app/lib/features/reader/domain/sync_artifact.dart`
  - `flutter_app/lib/core/network/sync_api_client.dart`
- Goal:
  - keep Flutter data models aligned with backend sync artifacts
- Non-goals:
  - no widget tree changes

### F2: Playback and Reader UX

- Owner files:
  - `flutter_app/lib/features/reader/presentation/reader_screen.dart`
  - `flutter_app/lib/features/reader/state/reader_playback_controller.dart`
- Goal:
  - improve reader UX around content windows, seeking, and playback state
- Non-goals:
  - no network client changes

### F3: Realtime Job UX

- Owner files:
  - `flutter_app/lib/core/realtime/project_events_client.dart`
  - `flutter_app/lib/features/reader/state/reader_events_provider.dart`
- Goal:
  - improve realtime job-state handling and resilience
- Non-goals:
  - no sync model changes

### F4: Demo/Test Fixtures

- Owner files:
  - `flutter_app/lib/features/reader/state/sample_reader_data.dart`
  - `flutter_app/test/widget_test.dart`
- Goal:
  - keep demo content and tests aligned with production reader behavior
- Non-goals:
  - no runtime networking changes

### F5: Frontend Runbooks

- Owner files:
  - `flutter_app/README.md`
  - `docs/operations/local-run.md`
- Goal:
  - document the frontend’s production-adjacent run path and regression expectations
- Non-goals:
  - no Dart implementation changes

## Coordination Rules

- Each worker owns only the files listed above.
- Workers are not alone in the codebase and must not revert edits made by others.
- Cross-cutting changes require updating docs/tests only inside the assigned ownership slice.
- Each worker must report:
  - what changed
  - tests run
  - residual risk
