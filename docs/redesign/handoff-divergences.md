# Redesign v2 — Divergences from the design handoff

The v2 redesign is designer-led: the handoff (`Sabha v2 Component Redlines`,
`Sabha Desktop v2`, `Sabha v2 States`, and the token/responsive specs) is the
source of truth, and the implementation matches it unless there's a deliberate,
signed-off reason not to. This file is the running record of those deliberate
deviations — what the handoff specifies, what we shipped instead, and why — so
the gaps are intentional and reviewable rather than silent drift.

Only record **intentional** divergences here. Bugs and unfinished work aren't
divergences; fix or track those separately.

Each entry: the handoff spec, the change, the rationale (including the
trade-off accepted), and who decided.

---

## Typing indicator: reserved row → floating overlay

- **Date:** 2026-08-18
- **Decided by:** owner
- **Area:** composer typing indicator (`app/assets/stylesheets/application/composer.css`, `app/views/rooms/**/_*composer.html.erb`)

**Handoff spec** (`Sabha v2 Component Redlines`, `typingAnatomy` / `typingStates`):
a reserved 22px row above the composer card that is *"always present even when
empty, so the composer never shifts when someone starts or stops typing"*; the
idle state *"keeps its 22px. Nothing rendered inside."*

**What we shipped:** the indicator is an absolutely-positioned overlay that
floats in a 22px strip just above the composer card, painting the canvas
background. It reserves **no** layout space — idle or active — and appears only
while someone is typing.

**Why:** the always-present empty row read as dead space above the composer.
The overlay reclaims that space while preserving the handoff's core intent — the
composer never shifts as typing starts or stops, because the strip is out of
flow in every state. Removing the reserved row also let the provisional thread
composer drop its placeholder row without shifting on swap to the real panel.

**Trade-off accepted:** while a name is showing, the strip can overlap the
bottom whitespace of the last message (and, in a very short conversation, the
last line itself) for those 22px. The alternatives — collapsing the row on idle
(nudges the composer up/down every time typing toggles) or keeping the reserved
row (the dead space we're removing) — were both rejected in favor of this.

**Knock-on:** the reserved row had been doubling as invisible padding that
lifted the "jump to newest" pill clear of the composer card. With the row gone
the pill sat on the card, so its clearance in `messages.css` was increased to
restore the gap.
