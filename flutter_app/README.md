# Flutter App

The Flutter client renders the canonical reading model, plays audio, and highlights tokens using the sync artifact.

Constraints:

- no WebView-based EPUB reader in MVP
- playback time is the source of truth
- highlight updates must stay cheap and smooth

Implementation must follow:

- [docs/design/ui-theme.md](/home/eslam/Storage/Code/Sync/docs/design/ui-theme.md)
- [docs/contracts/api.md](/home/eslam/Storage/Code/Sync/docs/contracts/api.md)
- [docs/contracts/sync-format.md](/home/eslam/Storage/Code/Sync/docs/contracts/sync-format.md)
