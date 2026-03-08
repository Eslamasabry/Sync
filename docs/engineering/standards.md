# Engineering Standards

## Version Baseline

- Python: 3.12
- Flutter: stable channel, Dart 3.x
- PostgreSQL: 16
- Redis: 7

## Backend Libraries

### API and core

- `fastapi`
- `uvicorn`
- `pydantic`
- `sqlalchemy`
- `alembic`
- `psycopg`
- `httpx`
- `structlog`

### Jobs and storage

- `celery`
- `redis`
- `boto3` or `minio` client for S3-compatible storage

### Alignment and media

- `ebooklib`
- `lxml`
- `rapidfuzz`
- `numpy`
- `orjson`
- `whisperx`
- `ffmpeg` as a system dependency

Notes:

- Keep the forced aligner behind an adapter so MFA or Aeneas can be swapped without API changes.

## Flutter Libraries

- `flutter_riverpod`
- `go_router`
- `dio`
- `web_socket_channel`
- `just_audio`
- `audio_session`
- `freezed`
- `json_serializable`
- `scrollable_positioned_list`
- `google_fonts`

Notes:

- State lives in Riverpod providers.
- API models are generated where practical.
- Reader rendering stays custom and token-aware.

## Formatting and Static Checks

### Python

- formatter and linter: `ruff`
- type checking: `mypy`
- tests: `pytest`

### Flutter

- formatter: `dart format`
- static analysis: `flutter analyze`
- tests: `flutter test`

## Code Style

- Prefer small modules with explicit interfaces.
- Keep IO boundaries visible.
- Use typed DTOs for all external contracts.
- Do not let worker code import Flutter assumptions.
- Do not let UI code re-derive backend alignment logic.

## Git and Delivery

- Main branch stays releasable.
- Small PRs are preferred over broad refactors.
- Contract changes require docs in the same change.
- Add regression fixtures before changing matching or export behavior.
