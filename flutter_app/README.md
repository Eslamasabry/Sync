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

Run with a real backend project:

```bash
cd flutter_app
flutter run \
  --dart-define=SYNC_API_BASE_URL=http://localhost:8000/v1 \
  --dart-define=SYNC_PROJECT_ID=<project-id>
```

Implementation must follow:

- [docs/design/ui-theme.md](/home/eslam/Storage/Code/Sync/docs/design/ui-theme.md)
- [docs/contracts/api.md](/home/eslam/Storage/Code/Sync/docs/contracts/api.md)
- [docs/contracts/sync-format.md](/home/eslam/Storage/Code/Sync/docs/contracts/sync-format.md)
