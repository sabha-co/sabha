# Redesign v2 — divergences from the handoff

The handoff is the source of truth; we match it unless there's a deliberate reason not to. This records those departures — handoff vs. what shipped vs. why. Intentional divergences only (bugs and unfinished work are tracked elsewhere); all owner-decided.

## Typing indicator — reserved row → floating overlay
- **Handoff:** an always-present 22px row above the composer, so it never shifts when typing toggles.
- **Shipped:** an out-of-flow overlay reserving no space, shown only while someone types.
- **Why:** the empty row read as dead space; the composer still never shifts, since the strip is out of flow in every state. (Knock-on: the "jump to newest" pill lost that row's padding, so its clearance in `messages.css` was bumped.)

## Reactions — grouped chips
Aligned to the handoff (one chip per emoji, stacked reactor avatars, accent tint when you're in it, trailing ＋). Residual deviations:
- **Not optimistic** — round-trips and replaces the grouped container rather than inserting your avatar before the broadcast confirms; grouping makes an optimistic insert materially harder.
- **+N cap** — a chip stacks up to `Boost::AVATARS_SHOWN` (5) avatars then collapses to `+N`; the handoff stacks unboundedly.
- **Hover bar toggles** — a quick reaction you've already used is tinted, and clicking it removes it; the handoff's quick reactions are stateless.

## Composer format bar — no `#` control
- **Handoff:** `B I S </> | @ #`.
- **Shipped:** `B I S </> | @`.
- **Why:** `@` backs a real feature (mentions via `Message::Mentionee`); there's no `#room` reference syntax to wire a `#` to, so it would insert a dead character. Adding it is a feature, not a reskin.

## Original room — no delete control (vs. disabled)
- **Handoff:** Delete shown but disabled on the original room, with "The original room can't be deleted — it is where every new member lands."
- **Shipped:** the row is omitted entirely (`deletable = can_administer && !room.original?`); the rule stays enforced server-side (`CannotDeleteOriginalError`).
- **Why:** a control that can never be used reads as dead chrome. **Trade-off:** the "why" only surfaces as a server error.

## Quick profile — centered scrim card → anchored popover
- **Handoff:** a centered 320px modal over a dimmed scrim, click-to-open.
- **Shipped:** a `<details>` popover (`popup_controller`) anchored to the avatar, lazy-loading the profile, no scrim.
- **Why:** a profile peek should stay tied to the avatar and leave the conversation visible; a full-scrim modal (how the prototype demoed any popup) pulls focus off the page for a lightweight lookup.

## New room name — pre-filled default (vs. placeholder-empty)
- **Handoff:** an empty name field showing the placeholder "Name the room".
- **Shipped:** the field is pre-filled with a type default ("New room" / "New forum", from `DEFAULT_ROOM_NAME`/`DEFAULT_FORUM_NAME`) and autofocused; the placeholder never renders while a value is present.
- **Why:** a room is creatable in one action with a sensible, type-named default rather than blocking on an empty `required` field, so an un-renamed room still reads sensibly in the sidebar. **Trade-off:** the placeholder is inert, and the user edits an existing value rather than typing into an empty field.
