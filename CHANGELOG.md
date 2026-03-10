# Changelog

## v0.1.6

- Library now stays at the center of the app instead of preloading the reader on startup
- Import now blocks `Start Sync` until the configured server is actually reachable and the token is valid
- Continue-reading actions stay disabled until a real readable book exists instead of pushing users into pending reader states
- Backend asset uploads now stream through temporary files instead of reading entire audiobook uploads into memory first

## v0.1.5

- Fixed the first-load Railway client bug where the app opened a project WebSocket without a selected project ID
- Reader realtime subscriptions now stay idle until a real project target exists, preventing repeated WebSocket failures on empty-state startup

## v0.1.4

- Library now starts in the right place for first-time users instead of dropping into a project-less reader state
- Device folder scanning reads real EPUB metadata and cover art locally, then surfaces discovered books as a first-class shelf
- Import flow now emphasizes recognized book details, clearer missing-file guidance, and smarter scanned-folder actions for full vs audio-only matches
- Post-import sync progress now refreshes live in the library while the alignment job is still running

## v0.1.3

- Railway deployment baseline for the backend with a committed `Dockerfile`, `Procfile`, and operator docs for inline-mode hosting
- Stronger development-mode CORS defaults so Flutter web can reach the API from localhost without manual env setup
- Reader and library UI overhaul with calmer shell chrome, cleaner typography, and a more workspace-like library
- Slimmer reader hierarchy with reduced status clutter and a text-first reading surface

## v0.1.2

- Stronger library project catalog with current-target state, clearer project cards, and direct workspace vs reader actions
- Project workspace guidance now explains the next recommended move based on sync state and offline readiness
- Per-project audio download and removal actions are available directly from the library, not only from the reader target
- Continued frontend polish across library flows to reduce status clutter and make device-side project management clearer

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
