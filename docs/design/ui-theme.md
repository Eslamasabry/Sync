# UI Theme Baseline

## Design Direction

The reader should feel like a crafted reading tool, not a generic mobile dashboard. The base visual language is:

- warm paper surfaces
- dark ink typography
- brass-like accent color for active playback
- restrained motion

This keeps the product readable for long sessions while still feeling distinct.

## Theme Modes

MVP supports:

- `paper` as the default mode
- `night` as the low-light mode

Sepia-style reading is the primary visual identity. Dark mode is functional, not flashy.

## Color Tokens

### Paper

| Token | Value | Usage |
| --- | --- | --- |
| `bg.base` | `#F6F0E2` | main background |
| `bg.elevated` | `#FFF9ED` | cards and sheets |
| `text.primary` | `#241A12` | body text |
| `text.muted` | `#6A5849` | secondary text |
| `accent.primary` | `#B8742A` | active word, progress, CTAs |
| `accent.soft` | `#E6C79B` | soft highlight fill |
| `border.subtle` | `#D8C8AE` | dividers |
| `status.error` | `#A33A2B` | failures |
| `status.success` | `#3F6B45` | completed jobs |

### Night

| Token | Value | Usage |
| --- | --- | --- |
| `bg.base` | `#171411` | main background |
| `bg.elevated` | `#211C17` | panels |
| `text.primary` | `#F4E7CF` | body text |
| `text.muted` | `#C6B79E` | secondary text |
| `accent.primary` | `#E29A47` | active word and progress |
| `accent.soft` | `#5B4327` | soft highlight fill |
| `border.subtle` | `#3D332A` | dividers |

## Typography

- Display: `Fraunces`
- Reading body: `Source Serif 4`
- UI labels and controls: `IBM Plex Sans`
- Mono and debug UI: `JetBrains Mono`

Rules:

- The reading surface uses serif body text.
- Dense control surfaces use the sans family.
- Avoid default system font stacks as the main brand voice.

## Highlight Behavior

- Active word uses `accent.primary` text or underline emphasis depending on context.
- Current phrase can use `accent.soft` background.
- Do not animate every token with fades; update sharply and predictably.
- Smooth scroll should follow phrase groups, not every single word jump.

## Motion

- Progress changes: 120 to 180 ms
- Sheet and panel transitions: 180 to 240 ms
- Reader scroll following: eased and minimal

Avoid:

- springy bounce animations
- decorative parallax
- constant shimmer or pulse effects

## Layout Rules

- Reader text width should stay comfortable on tablet and desktop.
- Playback controls stay pinned to the bottom region.
- Scrubber, speed, and skip actions must remain reachable with one hand on phones.
- The reader must tolerate large text and accessibility scaling.

## Accessibility

- Contrast should meet WCAG AA at minimum.
- Highlight cannot rely on color only; pair with weight, underline, or background change.
- The current spoken position must remain understandable in both paper and night themes.
