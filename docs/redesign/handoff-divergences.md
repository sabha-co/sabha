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

---

## Reactions: grouped chips (aligned to the handoff) with two residual deviations

- **Date:** 2026-08-18
- **Decided by:** owner
- **Area:** reactions/boosts (`app/models/message.rb`, `app/models/boost.rb`, `app/views/messages/boosts/**`, `app/javascript/controllers/boost_toggle_controller.js`, `app/assets/stylesheets/application/boosts.css`)

This one mostly *closes* a divergence rather than opening one. The chips previously
followed Campfire's per-person model (one avatar + emoji + inline delete per
booster); the handoff (`Sabha v2 Component Redlines`, reactions anatomy #4)
specifies one chip per emoji with the reactors' avatars stacked, accent-tinted
when you're in it, and a trailing `＋`. We now render that: grouped chips, a
click-to-toggle that adds or removes the current user's reaction, and the `＋`
pill (shown only alongside an existing reaction row, per `f.hasRx`). Two
deliberate deviations remain:

**Chips are not optimistic.** Handoff behaviour: *"the chip appears with your
avatar before the Turbo Stream confirms, and reverts if the broadcast
disagrees."* We instead round-trip to the server and replace the whole grouped
container (idempotent, so the author's direct response and the broadcast
converge). Grouped chips make an optimistic insert materially harder — a new
reaction may start a chip or just add one avatar to an existing one — so we
took the simpler, always-consistent path. Revisit if the round-trip feels slow.

**A `+N` avatar cap the handoff doesn't specify.** The handoff just stacks
avatars. A heavily-reacted chip would grow unboundedly wide, so a chip stacks up
to `Boost::AVATARS_SHOWN` (5) avatars and collapses the rest into a trailing
`+N`. This is an addition, not a contradiction, but it's a decision the redlines
don't cover.

**The hover bar reflects and toggles the current user's reactions.** The
handoff's quick reactions are stateless shortcuts. We highlight a quick reaction
the current user has already used (accent tint, `reaction_bar_controller`) and
turn a click on a highlighted one into a removal, so the bar reads as a live
toggle. Another addition beyond the redlines, in the same spirit as marking a
chip as yours.
