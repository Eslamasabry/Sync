# Release Readiness

This project is release-ready for open-source consumers only when these gates are green:

- backend CI passes on GitHub
- Flutter CI passes on GitHub
- `make local-regression-corpus-gate` passes on a real host
- `GET /v1/health` and `GET /v1/ready` behave correctly in the target deployment
- at least one real EPUB + audiobook smoke run succeeds end to end after deployment

## Backend Gate

Required locally:

```bash
cd /home/eslam/Storage/Code/Sync/backend
.venv/bin/ruff check src tests
.venv/bin/mypy src
.venv/bin/pytest -q
```

## Flutter Gate

Required locally:

```bash
cd /home/eslam/Storage/Code/Sync/flutter_app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Runtime Gate

For a candidate deploy:

- health endpoint returns `200`
- readiness endpoint returns `200`
- WebSocket upgrades work through the reverse proxy
- uploaded audio streams back through `GET /v1/projects/{project_id}/assets/{asset_id}/content`

## Alignment Gate

Run the real corpus gate:

```bash
cd /home/eslam/Storage/Code/Sync
make local-regression-corpus-gate
```

Review:

- `tmp/regression-corpus/summary.json`
- per-title `metrics.json`
- any threshold failures before release
