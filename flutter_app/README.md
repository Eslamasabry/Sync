# Flutter App

The Flutter client renders the canonical reading model, plays audio, and highlights tokens using the sync artifact.

Constraints:

- no WebView-based EPUB reader in MVP
- playback time is the source of truth
- highlight updates must stay cheap and smooth

Current baseline:

- typed API client for reader model and sync artifact
- Riverpod async project loading with demo fallback only for the default `demo-book` project
- local playback/theme controller separated from remote content loading
- sync-driven token highlighting UI scaffold

## CI Expectations

GitHub Actions validate the Flutter app with:

- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test`

Run those locally before opening a release-facing PR.

## Runtime Inputs

The app currently reads two compile-time values:

- `SYNC_API_BASE_URL`: backend API root, default `http://localhost:8000/v1`
- `SYNC_PROJECT_ID`: project UUID or the fallback `demo-book`

The WebSocket URL is derived automatically from `SYNC_API_BASE_URL`:

- `http://...` -> `ws://...`
- `https://...` -> `wss://...`

## Run With A Real Backend Project

Local desktop or iOS simulator:

```bash
cd flutter_app
flutter run \
  --dart-define=SYNC_API_BASE_URL=http://localhost:8000/v1 \
  --dart-define=SYNC_PROJECT_ID=<project-id>
```

Android emulator:

```bash
cd flutter_app
flutter run \
  --dart-define=SYNC_API_BASE_URL=http://10.0.2.2:8000/v1 \
  --dart-define=SYNC_PROJECT_ID=<project-id>
```

Physical device on the same LAN as the backend host:

```bash
cd flutter_app
flutter run \
  --dart-define=SYNC_API_BASE_URL=http://<host-lan-ip>:8000/v1 \
  --dart-define=SYNC_PROJECT_ID=<project-id>
```

If you use a physical device, the backend must listen on a non-loopback host. For example:

```bash
cd /home/eslam/Storage/Code/Sync/backend
.venv/bin/uvicorn sync_backend.main:app --host 0.0.0.0 --port 8000 --reload
```

## Local End-To-End Flow

Docker-backed path:

```bash
cd /home/eslam/Storage/Code/Sync
make dev-up
make backend-install
make backend-run
```

In another shell:

```bash
cd /home/eslam/Storage/Code/Sync/flutter_app
flutter run \
  --dart-define=SYNC_API_BASE_URL=http://localhost:8000/v1 \
  --dart-define=SYNC_PROJECT_ID=<project-id>
```

Host-services path:

- install and start `postgresql` and `redis-server` on the machine
- keep `backend/.env` pointed at `localhost`
- run `make backend-run` and `make worker-run`
- launch Flutter with the correct base URL for your target runtime

For a complete smoke run, prefer the repo scripts documented in [local-run.md](/home/eslam/Storage/Code/Sync/docs/operations/local-run.md).

## Current Playback Behavior

- real audio playback is used when the backend project loads and the sync artifact references uploaded audio assets
- demo fallback stays available when the API is offline, but uses the simulated timeline instead of `just_audio`
- real projects now respect backend artifact `download_url` values for both reader-model and sync payload loading

## Production-Adjacent Usage Notes

- Browser clients require backend CORS configuration through `CORS_ALLOW_ORIGINS` or `CORS_ALLOW_ORIGIN_REGEX`.
- Reverse proxies must pass both HTTP and WebSocket traffic for `/v1/ws/projects/{project_id}`.
- Use `https://` in `SYNC_API_BASE_URL` for deployed environments so the client upgrades to `wss://` automatically.
- The client assumes uploaded audio is streamable from `GET /v1/projects/{project_id}/assets/{asset_id}/content`.
- When the API is unreachable, the app intentionally falls back to demo content only for the default `demo-book` project. Real project ids now surface a load error instead of silently masking backend issues.

Implementation must follow:

- [docs/design/ui-theme.md](/home/eslam/Storage/Code/Sync/docs/design/ui-theme.md)
- [docs/contracts/api.md](/home/eslam/Storage/Code/Sync/docs/contracts/api.md)
- [docs/contracts/sync-format.md](/home/eslam/Storage/Code/Sync/docs/contracts/sync-format.md)
