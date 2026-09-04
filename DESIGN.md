---
name: Sabha
description: Calm, self-hosted team chat — own your bytes, keep conversation the hero.
colors:
  indigo: "oklch(51.9% 0.202 276)"
  indigo-bg: "oklch(95.5% 0.019 283)"
  indigo-border: "oklch(89.5% 0.045 284)"
  indigo-lift: "oklch(65.8% 0.159 280)"
  ink: "oklch(20.4% 0.007 258)"
  ink-light: "oklch(33.9% 0.014 257)"
  ink-muted: "oklch(50.4% 0.018 257)"
  ink-subtle: "oklch(70.3% 0.018 256)"
  paper: "oklch(100% 0 0)"
  paper-sunk: "oklch(98.5% 0.001 286)"
  paper-hover: "oklch(97.6% 0.003 265)"
  line: "oklch(93.4% 0.006 265)"
  line-soft: "oklch(95.8% 0.004 271)"
  negative: "oklch(57% 0.168 26)"
  negative-wash: "oklch(98% 0.08 22)"
  positive: "oklch(57.4% 0.135 155)"
  alert: "oklch(61% 0.129 70)"
typography:
  display:
    fontFamily: "Instrument Sans, -apple-system, BlinkMacSystemFont, Aptos, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "2.4rem"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Instrument Sans, -apple-system, BlinkMacSystemFont, Aptos, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "1.8rem"
    fontWeight: 700
    lineHeight: 1.2
  title:
    fontFamily: "Instrument Sans, -apple-system, BlinkMacSystemFont, Aptos, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "1.4rem"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "Instrument Sans, -apple-system, BlinkMacSystemFont, Aptos, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "Instrument Sans, -apple-system, BlinkMacSystemFont, Aptos, Roboto, Helvetica, Arial, sans-serif"
    fontSize: "0.8rem"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.02em"
  mono:
    fontFamily: "JetBrains Mono, ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "0.8rem"
    fontWeight: 400
    lineHeight: 1.5
rounded:
  sm: "8px"
  md: "0.5em"
  pill: "999px"
  circle: "50%"
spacing:
  inline: "1ch"
  inline-half: "0.5ch"
  block: "1rem"
  block-half: "0.5rem"
  block-double: "2rem"
  row: "9px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.sm}"
    padding: "0.5em 1.1em"
  button-primary-hover:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  button-secondary:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "0.5em 1.1em"
  button-negative:
    backgroundColor: "{colors.negative}"
    textColor: "{colors.paper}"
    rounded: "{rounded.sm}"
    padding: "0.5em 1.1em"
  input-default:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "0.6em 0.8em"
  card-default:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "1rem 1ch"
---

# Design System: Sabha

## Overview

**Creative North Star: "The Quiet Workshop"**

Sabha's visual world is a quiet workshop — warm wood on the walls, precise tools on the bench, and generous open space in between. Nothing competes with the work. The interface is the bench, not the project: tonal surfaces, 1px borders, and 8px corners form a calm, reliable scaffold so messages, people, and reactions carry all the color and life. It's calm, precise, and confident — opinionated in its restraint, Campfire/HEY in its lineage, without ever feeling corporate or clever.

Density is low and breathing. The message stream is the hero; chrome recedes. The sidebar docks, collapses to a rail, or becomes a drawer, but never crowds the conversation. Surfaces are flat by default and lift only when they must — a popover, a panel, a modal. Personality arrives through thoughtful defaults: avatar warmth, measured transitions, and rem-based rhythm that respects zoom and preference — not through decoration.

**Key Characteristics:**
- Tonal layering first — `bg / raised / sunk / hover` and `border` do the depth work; shadows only on lift.
- Tactile and precise — 8px radius, 1px borders, `scale(0.97)` press, `150ms` ease, all in `rem`/`em`.
- Content-first — generous whitespace, minimal chrome, message authors and boosts as the color.
- Warm and reliable — OKLch paper and ink, indigo accent, earth-tone avatars; red only for destructive.
- Respectful by default — WCAG AA, keyboard, SR, `max(16px, 1em)` inputs, rem-scale throughout.

## Colors

A paper-and-ink foundation with a single selectable accent — indigo is the default; Ink, Forest, Rust, Plum, Teal, Ocean, and Amber are the workspace personalities. Warm earth tones identify people; cool grays provide structure.

### Primary
- **Indigo** (`oklch(51.9% 0.202 276)`): The default brand accent. Interactive elements, links, selection, and primary emphasis. Applied via `--lch-accent` / `--color-accent-brand` / `--color-link`; selection tints are `indigo-bg` (`oklch(95.5% 0.019 283)`) and `indigo-border` (`oklch(89.5% 0.045 284)`). On dark, the lift `oklch(65.8% 0.159 280)` takes over and tints derive as `lift / 0.15` and `lift / 0.34`.
- **Indigo Lift** (`oklch(65.8% 0.159 280)`): Dark-mode accent. Not used directly on light; bound only in dark scopes so contrast holds.

### Secondary (workspace accents — mutually exclusive via `[data-accent]`)
- **Ink** (`oklch(32.9% 0.025 266)`), **Forest** (`oklch(48.6% 0.090 165)`), **Rust** (`oklch(52.4% 0.130 41)`), **Plum** (`oklch(47.7% 0.138 317)`), **Teal** (`oklch(50% 0.095 192)`), **Ocean** (`oklch(50% 0.150 253)`), **Amber** (`oklch(52% 0.110 80)`): Each carries its own `bg / bd / lift` triple. No mixing — one hue per workspace.

### Tertiary
- **Alert Amber** (`oklch(61% 0.129 70)`): Starred markers, warnings — used sparingly for attention.
- **Positive Green** (`oklch(57.4% 0.135 155)`): Success states.
- **Negative Red** (`oklch(57% 0.168 26)` with wash `oklch(98% 0.08 22)`): Destructive actions, mentioned-message tint (`oklch(57% 0.168 26 / 0.09)` hover `0.14`; dark `0.18` / `0.24`).

### Neutral
- **Ink** (`oklch(20.4% 0.007 258)`): Primary text `--color-text`.
- **Ink Light** (`oklch(33.9% 0.014 257)`): `--color-text-lighter`.
- **Ink Muted** (`oklch(50.4% 0.018 257)`): Load-bearing secondary text `--color-text-muted` — the minimum for WCAG AA on paper.
- **Ink Subtle** (`oklch(70.3% 0.018 256)`): `--color-text-subtle` — decorative meta only (timestamps, counts); clears 3:1 but not 4.5:1.
- **Paper** (`oklch(100% 0 0)`): `--color-bg` and `--lch-raise` (raised surface).
- **Paper Sunk** (`oklch(98.5% 0.001 286)`): `--color-bg-sunk` — inset/code/pre backgrounds.
- **Paper Hover** (`oklch(97.6% 0.003 265)`): `--color-bg-hover`.
- **Line Soft** (`oklch(95.8% 0.004 271)`): `--color-border` — default divider.
- **Line** (`oklch(93.4% 0.006 265)`): `--color-border-dark` — stronger rule.
- **Contrast Sidebar** (`oklch(21% 0.01 277)` light theme; `oklch(16% 0.008 278)` dark theme): the default sidebar surface. It stays dark in both themes and steps darker than the page in dark mode so the two-tone hierarchy does not invert.
- **Bench Edge** (`oklch(96% 0.007 84)`): `--color-bg-side` — the warm near-paper Match preference; a shade off `paper` for a quiet two-tone split. Hover `oklch(93% 0.011 82)`, divider `oklch(88.5% 0.013 82)`. In dark mode Match uses the dark bench tokens.
- **Scrim** (`oklch(0% 0 0 / 0.16)`): `--color-scrim` — sidebar drawer overlay; dialog backdrop is `oklch(0% 0 0 / 0.5)`.

### Named Rules
**The Accent-Rarity Rule.** The accent fills ≤10% of any screen — links, selection, and one primary control at most. Its rarity is the point; everything else is paper, ink, and line.
**The Subtle-Is-Decorative Rule.** `ink-subtle` never carries load-bearing information. If it must be read, use `ink-muted` or darker.
**The Eight-Personalities Rule.** One `[data-accent]` per workspace, no mixing. A new accent introduces exactly four values (`--lch-accent`, `--lch-accent-bg`, `--lch-accent-bd`, `--lch-accent-lift`).

## Typography

**Display Font:** Instrument Sans (with -apple-system, BlinkMacSystemFont, Aptos, Roboto, Helvetica, Arial, sans-serif)
**Body Font:** Instrument Sans (same stack)
**Label/Mono Font:** JetBrains Mono (with ui-monospace, SFMono-Regular, Menlo, monospace)

**Character:** Humanist warmth for UI and body, precise mono for code. Instrument is self-hosted variable (400–700, plus italic) over a system fallback that can be forced via `data-typeface="system"`; JetBrains Mono is the code voice. Six-level scale breathes; weight is capped at 700 so emphasis renders real glyphs, not synthesized 900.

### Hierarchy
- **Display** (700, 2.4rem / `xx-large`, 1.1, -0.02em): Marketing/empty-state hero only. Rare.
- **Headline** (700, 1.8rem / `x-large`, 1.2): Page/room titles, forum headers.
- **Title** (600, 1.4rem / `large`, 1.3): Section titles, card heads, dialog titles.
- **Body** (400, 1rem / `medium`, 1.4): Messages, form text, prose. Max line length ~50ch on forms (fieldset) and ~65–75ch on reading surfaces. Base for rem scale — respected by zoom.
- **Small** (400, 0.85rem / `small`): Secondary UI, metadata.
- **X-Small** (400, 0.8rem / `x-small`): Timestamps, labels, chrome. Label variant adds `uppercase + 0.02em` tracking.
- **Mono** (400, 0.8rem, 1.5, JetBrains Mono): Code, `code`/`pre` blocks, with `0.2em 0.4em` padding, `1px solid --color-border-dark`, `0.3em` radius; `pre` wraps.

### Named Rules
**The Rem-Respect Rule.** All type, padding, and hit areas stay in `rem`/`em`/`ch` (8px radius is the one px-pinned exception). Zoom must scale everything.
**The 700-Cap Rule.** Never request 900 weight — Instrument tops at 700; `b, strong` are capped to 700 to avoid synthesis.

## Layout

**Spatial model:** A rem-anchored rhythm using `--block-space: 1rem` / `--inline-space: 1ch` with half (`--block-space-half`) and double (`--block-space-double`) steps. Utilities `.pad`, `.gap`, `.margin-*` consume these exact values so spacing composes predictably.

**Grid & containers:** Sidebar + main content. The dark Contrast skin is the default; the page-matched Bench Edge skin is an optional per-device preference. Sidebar: docks left ≥1280px, collapses to 60px icon rail from 834–1279px (expands over content on demand with `-18px 0 44px` panel shadow), becomes a drawer over a `16%` scrim below 834px. Main content is the message stream or forum post gallery; forum forces post-gallery layout, not a stream.

**Density:** Default `--space-row: 9px`, applied as the block padding on each sidebar row rather than as a gap between them (min-height 32px keeps touch targets); compact mode via `data-density="compact"` tightens to `4px` without shrinking hit area.

**Responsive:** Design mobile and desktop states together from the start. Utilities `.hide-on-mobile` / `.hide-on-desktop`, container `contain: inline-size`, and overflow snap regions provide staged disclosure without hidden gestures.

**Form width:** `fieldset` capped at `50ch`; dialog `--width: 50ch` centered with `calc(100dvw - 1ch*2)` max.

## Elevation & Depth

Flat by default. Depth comes from tonal layering (`--color-bg`, `--color-bg-raised`, `--color-bg-sunk`, `--color-bg-hover`, `--color-border` / `--color-border-dark`), not shadows. Shadows appear only as a response to lift on hover, elevation, or focus.

### Shadow Vocabulary
- **Raise** (`0 1px 2px oklch(0% 0 0 / 0.04)`): Subtle lift for raised surfaces.
- **Pop** (`0 3px 12px oklch(0% 0 0 / 0.1)`): Cards, tooltips, quick profile on hover/open.
- **Panel** (`-18px 0 44px oklch(0% 0 0 / 0.2)`): Sidebar rail expansion and thread panels — the one directional shadow.
- **Overlay** (`0 12px 40px oklch(0% 0 0 / 0.28)`): Dialogs, popups, lightbox.

### Named Rules
**The Flat-By-Default Rule.** Surfaces are flat at rest. Shadows appear only as a response to state (hover, elevation, focus).
**The One-Directional Rule.** Only the sidebar panel casts a lateral shadow; everything else lifts vertically or overlays centrally.

## Shapes

Corner strategy is restrained, with a small named scale behind it. Controls default to **8px** — the `buttons.css` fallback in `border-radius: var(--btn-border-radius, 8px)` — for buttons, inputs, and cards. Alongside it sits a four-step token scale in `utilities.css`: `--border-radius-sm: 6px`, `--border-radius-md: 9px`, `--border-radius-lg: 12px`, `--border-radius-pill: 999px`. Radius isn't fully centralized yet: `0.5em` is still hardcoded at ~9 legacy sites (avatars, embeds, sidebar, actiontext), and those are `em`-based, so they scale with zoom rather than pinning — the token scale is the direction to converge on. Pills are an explicit opt-in (`--border-radius-pill` / `999px`, e.g. `.message-area__return-to-latest`); true circles (`50%`) are reserved for icon-only buttons. Avatars are **not** circles — since v2 they're a squircle, `--avatar-border-radius: 25%` (`avatars.css`), scaling with the avatar so a 36px message avatar reads as ~9px and the 17px boost-chip avatar keeps the same shape. Borders are hairline `1px solid` using `--color-border` / `--color-border-darker` / `--control-border` (73% lightness). Code and inline `code` use `0.3em` radius. Dialogs sit on a raised paper surface with a scrim backdrop, centered via transform — but there are **two** backdrops: the standard `<dialog>` uses `oklch(0% 0 0 / 0.5)` (`base.css`), while the lighter `.scrim-dialog` (reaction picker, role menu) uses a tinted `rgb(12 14 20 / 0.36)` (`dialogs.css`) — the one non-OKLch surface value, flagged for cleanup. Clipping is minimal — no decorative masks; geometry stays rectangular and honest.

## Components

### Buttons
Tactile and precise — ink on paper, or paper on ink, always with a border at rest.
- **Shape:** 8px radius (`--btn-border-radius: 8px`); circle variant (`50%`, `aspect-ratio: 1`, `--btn-size: 2.65em`, navbar `2.4em`, small `1.75em`); pill opt-in `999px`.
- **Primary (reversed):** `--btn-background: var(--color-text)` (ink), `--btn-color: var(--color-text-reversed)` (paper), `1px solid transparent`, padding `0.5em 1.1em`, weight 600, gap `0.5em`. Hover: `brightness(0.7)`, no outline spread. Active: `scale(0.97)`. Focus: `min(0.2em, 2px)` outline in `--color-link`, `150ms` transitions.
- **Secondary:** Paper background, ink text, `1px solid --color-border-darker`, same radius/padding. Hover adds `0 0 0 0.15em --color-border-darker`.
- **Negative:** `--color-negative` background, paper text.
- **Ghost/Plain:** `transparent` background/border, `padding: 0` for plain; `borderless` removes stroke. `faux` disables hover.
- **Avatar button:** `--avatar-border-radius`, no border, hover `brightness(0.7)`.

### Inputs / Fields
Stroke and sunk, focus via glow.
- **Style:** Paper background, `1px solid --color-border-dark` via `inputs.css`, 8px radius, padding `0.6em 0.8em`, `max(16px, 1em)` sizing to prevent iOS zoom, `font: inherit`.
- **Focus:** `box-shadow` / `outline-offset` `150ms` ease, outline in `--color-link`.
- **Code variant:** `.input--code` — `break-words whitespace-pre-wrap`, `font-family: var(--font-mono)`.

### Cards / Containers
- **Corner Style:** 8px (`border-radius: var(--border-radius, 1em)` default, cards pin to `0.5em` / 8px).
- **Background:** `--color-bg` or `--color-bg-raised`; sunk variant `--color-bg-sunk`.
- **Shadow Strategy:** Flat at rest; `shadow-pop` on hover/elevated (see Elevation).
- **Border:** `1px solid --color-border` at rest, `--color-border-dark` on emphasis.
- **Internal Padding:** `var(--block-space) var(--inline-space)` (`1rem 1ch`) via `.pad`.

### Navigation (Sidebar)
- **Style:** Dark Contrast is the intentional default in light and dark themes. It uses a 21% ground against the light page and a 16% ground against the 19.6% dark page, preserving a darker navigation edge in both. Match is the optional warm near-paper field in light mode and the dark bench surface in dark mode. List nodes use `--space-row: 9px` (compact 4px), 32px min-height; readable counts use `--color-text-muted`, never the decorative subtle token.
- **Typography:** Body/ small; active/mentioned states tinted via `indigo-bg` / red wash.
- **States:** Hover `bg-hover`; selected `indigo-bg` + `indigo-border`; mentioned `color-message-mentioned` wash.
- **Mobile:** Drawer over `scrim` with `shadow-panel`.

### Messages
- **Message bubble:** Paper surface, `border-radius: 0.5em` action bar, hover reveals `.message__actions` (border `1px solid --color-border-darker`).
- **Mentioned:** `color-message-mentioned` wash (`red / 0.09` light, `0.18` dark) hover `0.14` / `0.24`.
- **Boosts:** Inline pill reactions, hard-deleted on toggle.

### Chips / Boosts / Avatars
- **Avatar:** `--avatar-size` (`48px` small, `120px` large), squircle shape (`--avatar-border-radius: 25%`, not a circle). Identity resolves through a four-step chain (`Users::AvatarsController#show`): (1) an uploaded image (WebP variant); (2) for bots, a DiceBear bot style or the bundled `default-bot-avatar.svg`; (3) a **DiceBear**-generated SVG when `Dicebear.enabled?` (the `User::DicebearAvatar` concern, cached ~1 week); (4) initials on a warm earth-tone background (`avatar_background_color`) as the final fallback. The "warm earth tones" are only that last step — DiceBear is the default generated look when enabled, and earth tones are the saturated color only when it isn't.
- **Boosts:** Tactile pills with count, `color-selected` / `color-selected-dark` tints on active.

### Dialogs / Popups / Lightbox
- **Dialog:** `--width: 50ch`, centered `translate(-50%, -50%)`, `::backdrop oklch(0% 0 0 / 0.5)`. The lighter `.scrim-dialog` variant (picker/menu) overrides this with a tinted `rgb(12 14 20 / 0.36)` backdrop — the lone non-OKLch surface value (see Shapes).
- **Popups:** `shadow-overlay`, 8px radius, tonal border.
- **Lightbox:** Overlay with scrim, centered image, keyboard and SR accessible.

## Do's and Don'ts

### Do:
- **Do** use `rem`/`em`/`ch` for type, padding, and hit areas — 8px radius is the only px-pinned value.
- **Do** convey depth with `bg / raised / sunk / hover` and `border` before reaching for a shadow.
- **Do** reserve saturated color for avatars, boosts, and the single accent — let messages be the color.
- **Do** keep load-bearing text at `ink-muted` or darker; reserve `ink-subtle` for decorative meta only.
- **Do** design all three sidebar states (docked ≥1280px, rail 834–1279px, drawer <834px) from the start.
- **Do** cap emphasis at 700 weight and respect `data-typeface="system"` for platform-native fallback.

### Don't:
- **Don't** spread the accent — ≤10% of any screen, never as a full background wash.
- **Don't** use `ink-subtle` for readable information (it fails 4.5:1).
- **Don't** invent a second accent per workspace or mix accent hues on one screen.
- **Don't** add shadows at rest — lift only on hover/elevation/overlay.
- **Don't** use `px` for type or spacing; don't synthesize 900 weight.
- **Don't** hide primary navigation behind gestures or mystery icons — clarity over cleverness, always.
- **Don't** treat dark mode as an afterthought — every token has a `dark-lch-*` primitive and both `[data-theme="dark"]` and `prefers-color-scheme` paths must agree.
