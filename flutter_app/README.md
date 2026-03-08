# Flutter App

The Flutter client renders the canonical reading model, plays audio, and highlights tokens using the sync artifact.

Constraints:

- no WebView-based EPUB reader in MVP
- playback time is the source of truth
- highlight updates must stay cheap and smooth

Current baseline:

- typed API client for reader model and sync artifact
- Riverpod async project loading with demo fallback when the API is unavailable
- local playback/theme controller separated from remote content loading
- sync-driven token highlighting UI scaffold

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

## Production-Adjacent Usage Notes

- The current backend does not add CORS middleware, so Flutter web should be treated as unsupported unless you add a same-origin reverse proxy or explicit CORS support.
- Reverse proxies must pass both HTTP and WebSocket traffic for `/v1/ws/projects/{project_id}`.
- Use `https://` in `SYNC_API_BASE_URL` for deployed environments so the client upgrades to `wss://` automatically.
- The client assumes uploaded audio is streamable from `GET /v1/projects/{project_id}/assets/{asset_id}/content`.
- When the API is unreachable, the app intentionally falls back to demo content. That is convenient for local iteration but should not be mistaken for a healthy backend connection.

Implementation must follow:

- [docs/design/ui-theme.md](/home/eslam/Storage/Code/Sync/docs/design/ui-theme.md)
- [docs/contracts/api.md](/home/eslam/Storage/Code/Sync/docs/contracts/api.md)
- [docs/contracts/sync-format.md](/home/eslam/Storage/Code/Sync/docs/contracts/sync-format.md)
