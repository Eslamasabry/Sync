# Frontend World-Class Roadmap

## Purpose

This roadmap defines the next 10 frontend-focused sprints for `Sync`. The aim is not to add generic mobile-app polish. The aim is to turn the current synced-reader prototype into a reading product that feels deliberate, fast, reliable, and clearly better for audiobook plus EPUB reading than a normal ebook app.

## Planning Assumptions

- Sprint length: `2 weeks`
- Frontend team: `2 Flutter engineers + 1 product/design lead shared part-time`
- Working velocity: `34 points` per sprint
- Reserved buffer: `6 points` per sprint for regressions, backend drift, and release hardening
- Effective commitment target: `28 points`

## Product Standard

By the end of this roadmap, the frontend should feel:

- fast on mid-range Android devices
- legible for long reading sessions
- clearly aware of sync quality and audiobook structure
- reliable offline
- strong on phones, tablets, and desktop-width layouts
- private and self-hostable by default

## Design Rules

- The reading surface always wins over chrome.
- Sync-specific controls must feel native to reading, not bolted on.
- Every advanced feature must degrade cleanly when sync quality is imperfect.
- The app must stay usable when the backend is slow, unavailable, or still processing.

## Sprint 1: Reader Shell and Connection Confidence

### Sprint Goal

Make the app feel trustworthy on first launch by polishing connection setup, shell structure, and project state handling.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Runtime connection setup polish with validation, recent servers, and better failure copy — `8` — FE
2. Reader shell refinement for phone/tablet layouts and better loading/error empty states — `8` — FE
3. Project identity header with server, project, and auth state clarity — `5` — FE
4. Device-local privacy copy and safe reset flow for runtime config — `3` — FE
5. UI regression screenshots for paper and night themes — `4` — FE

### Dependencies

- Current runtime settings flow

### Risks

- Settings and project reload state can feel jarring.
  Mitigation: stage UI state transitions and keep prior project header visible during reload.

## Sprint 2: Reading Surface Excellence

### Sprint Goal

Make the text view feel premium for long sessions with better spacing, focus, and motion.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Reading typography controls: text size, line height, paragraph spacing, and column width — `8` — FE
2. Reader chrome minimization mode with distraction-free reading — `5` — FE
3. Better active-token and active-phrase treatment that does not rely on color alone — `5` — FE
4. Smooth phrase-follow scrolling with viewport anchoring — `6` — FE
5. Reduced-motion compatibility and motion tuning pass — `4` — FE

### Dependencies

- Sprint 1 layout stabilization

### Risks

- Aggressive auto-scroll can make readers lose context.
  Mitigation: anchor by phrase group and allow temporary manual override.

## Sprint 3: Navigation Built for Books

### Sprint Goal

Give readers fast, book-scale navigation instead of forcing linear scrolling.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Table of contents and section jump sheet from reader model sections — `8` — FE
2. Search inside normalized reader text with result jump and preview — `8` — FE
3. Persistent reading location restore across launches — `5` — FE
4. Inline progress model: book progress, section progress, and remaining time estimate — `4` — FE
5. Tap-to-jump from text, scrubber, and TOC with consistent animation rules — `3` — FE

### Dependencies

- Stable reader model sections

### Risks

- Search results may drift from sync token locations if normalization differs.
  Mitigation: search the canonical reader model only, not rendered text.

## Sprint 4: Sync Intelligence in the UI

### Sprint Goal

Expose sync quality and audiobook structure in a way that helps readers instead of alarming them.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Visual treatment for intro, outro, and unmatched narration spans — `6` — FE
2. Confidence-aware reader hints for weak alignment regions — `6` — FE
3. Gap inspector sheet with plain-language explanations — `6` — FE
4. Jump-to-content and jump-to-next-confident-span controls — `5` — FE
5. Sync-quality analytics and user-visible diagnostics copy polish — `5` — FE

### Dependencies

- Existing `content_start_ms`, `content_end_ms`, and gap metadata

### Risks

- Too much sync metadata can make the app feel technical.
  Mitigation: keep the default view calm and move details into expandable surfaces.

## Sprint 5: Offline That Actually Feels Offline

### Sprint Goal

Turn caching into a first-class offline reading experience instead of a backend fallback.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Unified project download manager for text, sync, and audio with byte-level progress — `8` — FE
2. Offline library state and per-project storage usage reporting — `6` — FE
3. Download prioritization for active chapter first, then full book — `6` — FE
4. Cache eviction and remove-local-copy UX hardening — `4` — FE
5. Offline failure handling for partial assets and stale cache — `4` — FE

### Dependencies

- Existing audio cache and download contracts

### Risks

- Long audiobooks may exceed device storage quickly.
  Mitigation: expose expected size early and support partial-first download strategy.

## Sprint 6: Annotation and Study Workflow

### Sprint Goal

Make the app useful for language learners and close readers, not just passive listening.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Bookmarks tied to sync positions and reader locations — `6` — FE
2. Saved highlights with timestamp and quote preview — `8` — FE
3. Notes attached to selections or positions — `6` — FE
4. Review tray for bookmarks, notes, and highlights — `5` — FE
5. Export/share format for personal annotations — `3` — FE

### Dependencies

- Stable reader navigation and location restore

### Risks

- Selection UX on dense tokenized text can feel brittle.
  Mitigation: support paragraph-level fallback and stable tap targets.

## Sprint 7: Audio-First Reading Controls

### Sprint Goal

Make audiobook playback controls feel advanced enough for power readers and language learners.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Phrase repeat, sentence repeat, and A/B loop controls — `8` — FE
2. Smarter skip controls based on sync spans instead of fixed seconds only — `6` — FE
3. Playback presets for study mode, commute mode, and bedtime mode — `5` — FE
4. Lock-screen, notification, and background playback UX polish — `5` — FE
5. Headphone and media-key behavior validation — `4` — FE

### Dependencies

- Stable sync span navigation

### Risks

- Looping exact spans with native audio can expose timing seams.
  Mitigation: test against real multi-file projects and add slight loop padding rules where necessary.

## Sprint 8: Accessibility and Inclusive Reading

### Sprint Goal

Raise the reader to a high accessibility bar for long-form reading and assisted listening.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Full large-text and display-scaling audit — `6` — FE
2. Screen reader semantics for playback state, current token, and navigation landmarks — `8` — FE
3. High-contrast and focus-state refinement beyond paper/night defaults — `5` — FE
4. One-handed reachable controls and handedness options — `5` — FE
5. Accessibility QA checklist and regression suite additions — `4` — FE

### Dependencies

- Stable UI shells and playback surfaces

### Risks

- Token-level announcements can overwhelm assistive tech users.
  Mitigation: expose phrase- or sentence-level summaries instead of speaking every token change.

## Sprint 9: Library, Intake, and Project Management

### Sprint Goal

Move from “single project reader” to “reader app” with a serious local library surface.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Library home with project cards, recent books, and download state — `8` — FE
2. Import and attach flow for EPUB and audio from device storage — `8` — FE
3. Processing queue and job history view — `6` — FE
4. Project details page with sync stats and asset state — `4` — FE
5. Empty-state and onboarding polish for first imported book — `2` — FE

### Dependencies

- Backend upload and job APIs already in place

### Risks

- Import UX can expose backend constraints too directly.
  Mitigation: use staged forms and friendly guidance instead of raw asset jargon.

## Sprint 10: Release-Quality Polish and Product Signature

### Sprint Goal

Finish the frontend with the kind of polish that makes the app feel memorable, stable, and ready to recommend.

### Capacity

- Target: `28 points`
- Buffer: `6 points`

### Committed Stories

1. Cross-device UI polish pass for phone, tablet, and desktop widths — `8` — FE
2. Performance pass on large books and long sync timelines — `8` — FE
3. Reader delight layer: subtle onboarding, tactile transitions, and polished soundness — `4` — FE
4. Frontend release checklist, screenshots, and store-ready artifact prep — `4` — FE
5. Final usability fixes from real-reader testing — `4` — FE

### Dependencies

- All prior core surfaces

### Risks

- Polishing late can uncover structural UI problems.
  Mitigation: keep a rolling usability log from Sprint 1 onward instead of waiting for the end.

## Critical Path

`Sprint 1` -> `Sprint 2` -> `Sprint 3` -> `Sprint 4` -> `Sprint 5`

Those five establish the core value:

- trustworthy connection and project setup
- excellent reading surface
- book navigation
- understandable sync quality
- real offline behavior

## Features Deferred Beyond This Roadmap

- social reading
- cloud account sync
- marketplace or public sync sharing
- on-device alignment generation
- community annotation sharing

## Definition of Done For Frontend Sprints

- `flutter analyze` passes
- `flutter test` passes
- affected reader states are covered by widget tests
- phone and tablet layouts are checked manually
- paper and night themes both reviewed
- no personal backend URLs, tokens, or hostnames are committed
