# Next 10 Tasks

## Purpose

This document defines the next 10 implementation tasks after the initial production-hardening tranche. The focus is making the project truly usable as a self-hosted open-source app: durable downloads, offline reading, stronger regression gates, and optional access control.

## Sequencing Rules

- Preserve the existing open-source default path. New auth and deployment work must stay optional.
- Finish backend download contracts before deep Flutter offline playback work.
- Prefer durable operator workflows and regression gates over cosmetic UI work.
- Keep the reader model and sync artifact contracts stable while widening offline support.

## Lane Split

- Backend lane: `BE1`, `BE2`, `BE3`, `BE4`, `BE5`
- Frontend lane: `FE1`, `FE2`, `FE3`, `FE4`, `FE5`

## Critical Path

`BE1` -> `BE2` -> `FE1` -> `FE2` -> `FE3`

## Task 1: BE1 Offline Audio Artifact Contract

### Goal

Expose stable metadata and download surfaces for audiobook assets so the Flutter client can cache them for offline playback.

### Scope

- audio asset metadata fields for offline download
- file size, content type, checksum, and duration
- stable per-asset download URLs
- contract examples in API docs

### Acceptance Criteria

- API responses for playable audio expose enough metadata for a download manager
- audio download URL format is documented and stable
- tests cover metadata shape and missing-audio edge cases

### Dependencies

- existing asset content route

## Task 2: FE1 Offline Audio Cache Manager

### Goal

Persist audio files locally after download so a synced project can be opened without network.

### Scope

- local cache directory and manifest
- per-project audio file persistence
- checksum or file-size validation against backend metadata
- cache read and cache cleanup logic

### Acceptance Criteria

- a downloaded project can resolve local audio files without network
- corrupted or partial files are detected and re-fetched
- tests cover cache hit, cache miss, and invalid cache cases

### Dependencies

- `BE1`

## Task 3: FE2 Project Download UX

### Goal

Give readers explicit controls to download, retry, and remove offline project data.

### Scope

- download action in the reader or project entry surface
- progress and failure states
- remove-local-copy action
- UI copy for storage and offline readiness

### Acceptance Criteria

- users can start and retry an offline download
- users can remove cached project data
- UI distinguishes downloaded, downloading, failed, and not-downloaded states

### Dependencies

- `FE1`

## Task 4: BE2 Stream-Safe Audio Delivery

### Goal

Serve long audio files safely for both streaming playback and resumable downloads.

### Scope

- HTTP range request support
- correct content length and content type headers
- resumable download behavior
- large-file route tests

### Acceptance Criteria

- range requests work for audio content routes
- large downloads resume cleanly
- client-facing headers are correct for cached audio downloads

### Dependencies

- `BE1`

## Task 5: FE3 Offline Playback Wiring

### Goal

Make the reader prefer local cached audio while preserving the existing sync timeline and highlighting.

### Scope

- choose local files when available
- preserve timeline offsets for multi-file audio
- keep existing highlighting and seeking behavior
- clear UI state when only text and sync are cached but audio is not

### Acceptance Criteria

- a project with cached audio plays and highlights fully offline
- a project with cached text but missing audio shows a clear partial-offline state
- tests cover online, cached-offline, and partial-offline behavior

### Dependencies

- `FE1`
- `FE2`
- `BE2`

## Task 6: BE3 Job Idempotency and Retry Rules

### Goal

Avoid duplicate alignment work and make failures safer to retry.

### Scope

- dedupe logic for equivalent alignment jobs
- explicit retry policy per stage
- stable terminal failure reasons
- operator-visible retry guidance

### Acceptance Criteria

- duplicate alignment requests do not spawn redundant work
- retriable failures are marked clearly
- tests cover duplicate job creation and retryable terminal states

### Dependencies

- current job orchestration pipeline

## Task 7: BE4 Regression Gate Hardening

### Goal

Turn the real-book regression corpus into a stronger release gate with stored results and per-title thresholds.

### Scope

- per-title thresholds and explanations
- aggregate pass/fail summary
- machine-readable stored run outputs
- release-readiness documentation updates

### Acceptance Criteria

- corpus gate fails with a clear reason when a case regresses
- aggregate results are saved in a stable machine-readable format
- release docs reference the hardened gate

### Dependencies

- current public-domain regression corpus

## Task 8: FE4 Reader Diagnostics Panel

### Goal

Show exactly what data the reader is using: live backend, cached artifacts, cached audio, or partial offline state.

### Scope

- source-state banner or diagnostics panel
- cache timestamp and status visibility
- latest alignment job status visibility
- offline readiness summary

### Acceptance Criteria

- users can tell whether playback is live, cached, or partial
- diagnostics include last cache time when applicable
- no demo fallback messaging appears for real cached projects

### Dependencies

- `FE1`
- existing offline artifact cache

## Task 9: BE5 Self-Hosted Auth Baseline

### Goal

Add optional auth so self-hosted operators can protect uploads, jobs, and realtime events.

### Scope

- bearer token validation for REST and WebSocket routes
- opt-in configuration only
- documentation for unsecured vs secured self-hosted modes
- tests for authenticated and unauthenticated paths

### Acceptance Criteria

- auth can be enabled without changing default open-source local flows
- protected routes reject missing or invalid tokens when auth is enabled
- WebSocket connections honor the same auth policy

### Dependencies

- existing API and realtime routes

## Task 10: FE5 Auth and Session Plumbing

### Goal

Allow the Flutter client to talk to secured self-hosted deployments.

### Scope

- bearer token injection for REST calls
- bearer token support for WebSocket connections
- app configuration path for local/self-hosted token use
- docs for token-enabled runs

### Acceptance Criteria

- Flutter works against both unsecured and token-protected deployments
- REST and WebSocket calls share the same auth configuration
- docs explain how to launch the app with auth enabled

### Dependencies

- `BE5`

## Delivery Order

1. `BE1`
2. `BE2`
3. `BE3`
4. `BE4`
5. `FE4`
6. `FE1`
7. `FE2`
8. `FE3`
9. `BE5`
10. `FE5`

## Risks

- Offline audio increases storage pressure and partial-download complexity on mobile devices.
- Auth must not break local contributor workflows or the current unauthenticated open-source path.
- Regression thresholds may need tuning as the corpus widens and WhisperX behavior changes.
