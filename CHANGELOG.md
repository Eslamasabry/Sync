# Changelog

## v0.1.1

- Runtime connection setup in the release APK, so users can point the app at their own backend without rebuilding
- Stronger reader UX with typography controls, focus mode, navigation/search, reading restore, and study workflows
- Improved accessibility semantics, enhanced contrast mode, and left-handed focus HUD placement
- Richer library surface with import flow, project snapshots, processing queue, and offline-state visibility
- Smarter sync-aware playback controls, loop handling, and clearer audio download progress reporting
- Project job-history API for library and operator views

## v0.1.0

- FastAPI backend for EPUB and audio ingestion, alignment jobs, artifact delivery, and realtime project events
- Canonical reader model and `sync.json` artifact generation with word-level timestamps
- Flutter reader with token highlighting, offline artifact caching, offline audio downloads, and playback diagnostics
- Public-domain regression corpus and release gating scripts
- Optional self-host bearer-token protection for project APIs and project-event WebSockets
- Self-host deployment templates for `systemd`, `nginx`, and env configuration
