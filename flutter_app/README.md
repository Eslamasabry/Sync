# Flutter App

The Flutter client renders the canonical reading model, plays audio, and highlights tokens using the sync artifact.

Constraints:

- no WebView-based EPUB reader in MVP
- playback time is the source of truth
- highlight updates must stay cheap and smooth

Current baseline:

- typed API client for reader model and sync artifact
- Riverpod async project loading with demo fallback only for the default `demo-book` project
- on-device caching for reader-model and sync artifact JSON after successful real-project loads
- on-device audio download and cache management for real projects
- local playback/theme controller separated from remote content loading
- sync-driven token highlighting UI scaffold

## CI Expectations

GitHub Actions validate the Flutter app with:

- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test`

Run those locally before opening a release-facing PR.

## Runtime Inputs

The app ships with compile-time defaults, but the release APK no longer depends on them. Users can open the in-app `Connection` sheet and save these values locally on the device:

- `SYNC_API_BASE_URL`: backend API root, default `http://localhost:8000/v1`
- `SYNC_PROJECT_ID`: project UUID or the fallback `demo-book`
- `SYNC_API_AUTH_TOKEN`: optional bearer token for protected self-hosted backends

Those saved values are device-local only. They are not written back into the repo, release asset, or GitHub Actions config.

The WebSocket URL is derived automatically from `SYNC_API_BASE_URL`:

- `http://...` -> `ws://...`
- `https://...` -> `wss://...`

## Run With A Real Backend Project

For release APK usage:

1. Install the APK from GitHub Releases.
2. Open the app.
3. Tap `Connection`.
4. Enter your backend URL, project ID, and optional auth token.
5. Save and reload.

Local desktop or iOS simulator:

```bash
cd flutter_app
flutter run \
  --dart-define=SYNC_API_BASE_URL=http://localhost:8000/v1 \
  --dart-define=SYNC_API_AUTH_TOKEN=<token> \
  --dart-define=SYNC_PROJECT_ID=<project-id>
```

Android emulator:

```bash
cd flutter_app
flutter run \
  --dart-define=SYNC_API_BASE_URL=http://10.0.2.2:8000/v1 \
  --dart-define=SYNC_API_AUTH_TOKEN=<token> \
  --dart-define=SYNC_PROJECT_ID=<project-id>
```

Physical device on the same LAN as the backend host:

```bash
cd flutter_app
flutter run \
  --dart-define=SYNC_API_BASE_URL=http://<host-lan-ip>:8000/v1 \
  --dart-define=SYNC_API_AUTH_TOKEN=<token> \
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
- after a successful real-project load, the app caches the normalized reader-model and sync artifact locally and reuses them when the backend is unreachable
- the reader can download project audio for offline playback and will prefer local cached files when they exist
- the reader now exposes a diagnostics panel that distinguishes local cached audio, mixed local plus streaming audio, streaming-only playback, and text-only sync mode
- cached offline mode now supports two states:
  - full offline: cached reader artifacts plus cached audio
  - partial offline: cached reader artifacts without fully downloaded audio
- real backend project ids no longer silently fall back to demo content for HTTP artifact errors; the app now shows a reader-state message for processing, missing, or failed backend artifacts

## Production-Adjacent Usage Notes

- Browser clients require backend CORS configuration through `CORS_ALLOW_ORIGINS` or `CORS_ALLOW_ORIGIN_REGEX`.
- Reverse proxies must pass both HTTP and WebSocket traffic for `/v1/ws/projects/{project_id}`.
- Use `https://` in `SYNC_API_BASE_URL` for deployed environments so the client upgrades to `wss://` automatically.
- When the backend is protected with `API_AUTH_TOKEN`, set the same value in `SYNC_API_AUTH_TOKEN` so both HTTP requests and project-event WebSocket connections authenticate correctly.
- The client assumes uploaded audio is streamable from `GET /v1/projects/{project_id}/assets/{asset_id}/content`.
- When the API is unreachable, the app intentionally falls back to demo content only for the default `demo-book` project. Real project ids now surface a load error instead of silently masking backend issues.

Implementation must follow:

- [docs/design/ui-theme.md](/home/eslam/Storage/Code/Sync/docs/design/ui-theme.md)
- [docs/contracts/api.md](/home/eslam/Storage/Code/Sync/docs/contracts/api.md)
- [docs/contracts/sync-format.md](/home/eslam/Storage/Code/Sync/docs/contracts/sync-format.md)
