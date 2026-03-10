# UI Theme Baseline

## Design Direction

The reader should feel like a crafted reading tool, not a generic mobile dashboard. The base visual language is:

- warm paper surfaces
- dark ink typography
- brass-like accent color for active playback
- restrained motion

This keeps the product readable for long sessions while still feeling distinct.
The current shell is intentionally split into:

- a restrained floating navigation dock
- a denser library workspace for project operations
- a calmer text-first reader surface

## Theme Modes

MVP supports:

- `paper` as the default mode
- `night` as the low-light mode

Sepia-style reading is the primary visual identity. Dark mode is functional, not flashy.

## Color Tokens

### Paper

| Token | Value | Usage |
| --- | --- | --- |
| `bg.base` | `#F3EDE1` | main background |
| `bg.elevated` | `#FFFBF3` | cards and sheets |
| `bg.chrome` | `#E8DED0` | app shell and dock surfaces |
| `text.primary` | `#1C140E` | body text |
| `text.muted` | `#54463A` | secondary text |
| `accent.primary` | `#B56B1F` | active word, progress, CTAs |
| `accent.soft` | `#E7C28F` | soft highlight fill |
| `border.subtle` | `#D3C2A6` | dividers |
| `shell.glow` | `#E6C08F` | shell ambient glow |
| `shell.shadow` | `#22160F08` | shell card shadow |
| `status.error` | `#A33A2B` | failures |
| `status.success` | `#3F6B45` | completed jobs |

### Night

| Token | Value | Usage |
| --- | --- | --- |
| `bg.base` | `#11100E` | main background |
| `bg.elevated` | `#1A1714` | panels |
| `bg.chrome` | `#0D0C0A` | app shell and dock surfaces |
| `text.primary` | `#F3E6CE` | body text |
| `text.muted` | `#D2BF9E` | secondary text |
| `accent.primary` | `#E5A158` | active word and progress |
| `accent.soft` | `#4A341F` | soft highlight fill |
| `border.subtle` | `#332A22` | dividers |
| `shell.glow` | `#4A341F` at 40% | shell ambient glow |
| `shell.shadow` | `#66000000` | shell card shadow |

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
- The app shell uses a floating dock rather than a flat system navigation slab.
- Shell chrome should feel denser and darker than the reading surface so content remains the focal plane.
- Library should feel like an operational workspace, not a single long settings sheet.

## Accessibility

- Contrast should meet WCAG AA at minimum.
- Highlight cannot rely on color only; pair with weight, underline, or background change.
- The current spoken position must remain understandable in both paper and night themes.
