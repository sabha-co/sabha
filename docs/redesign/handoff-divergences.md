# Redesign v2 — divergences from the handoff

The handoff is the source of truth; we match it unless there's a deliberate reason not to. This records those departures — handoff vs. what shipped vs. why. Intentional divergences only, all owner-decided (bugs are tracked elsewhere). Sidebar spec work still on the backlog is listed at the end under "Sidebar — not yet built".

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

## Sidebar room actions ⋯ — curated list vs. single item
- **Handoff:** the ROOMS ⋯ holds one item, Browse rooms ("a menu rather than a link so the header keeps room for more later").
- **Shipped:** six room-scoped items — Browse rooms, New forum, Hidden rooms, Notifications, Bookmarks, and (set apart by a hairline) Mark all as seen. Rebuilt on the shared `popover_menu_tag` so it matches the row menu's white surface.
- **Why:** those actions have no other sidebar home and were already reachable here; collapsing to one item would strand them. Redundant duplicates of the top utility nav (Activity, DMs, All messages) were dropped.

## Sidebar Forums header — no ＋ new forum
- **Handoff:** the FORUMS header carries a ＋ new forum action.
- **Shipped:** no ＋ on Forums; forum creation lives in the room actions ⋯ (New forum), permission-gated.
- **Why:** owner decision — keep a single, quiet forum-creation entry point.

## Account menu footer line — email vs. status
- **Handoff:** the collapsed footer shows a status/presence line under the name.
- **Shipped:** it shows the email.
- **Why:** there is no username/handle field on `User` and presence-setting is deferred, so the email is the only stable secondary identifier available.

## Account menu Community settings — staff-gated vs. always listed
- **Handoff:** Community settings is always listed for everyone; members get a read-only surface; a STAFF chip marks administrators.
- **Shipped:** shown to staff only (administrators + moderators), STAFF chip for both; admins link to editable settings, moderators to the read-only account view.
- **Why:** `edit_account` is administrator-only server-side and there is no read-only settings surface for plain members, so listing it for everyone would link to a forbidden page. **Trade-off:** plain members don't see the entry at all.

## Sidebar row ⋯ / unread badge — reserved column vs. shared right edge
- **Handoff:** on hover the ⋯ takes the unread badge's right edge, so read rows use the full name width.
- **Shipped:** the ⋯ keeps a reserved column (read rows are marginally narrower) and the badge stays put; on hover the ⋯ appears beside it.
- **Why:** absolute-positioning the ⋯ to reclaim the width painted a stray chip over the translucent selected/hover backgrounds, and hiding the badge on hover dropped mention counts. The handoff text itself sanctions the reserved column ("appears in place of nothing; the row does not grow").

## Density — localStorage vs. per-person preference
- **Handoff:** a comfortable/compact density control whose choice is stored per person as a server preference (§06 for the `--rowpad` 9px/4px values; §10 pairs it with collapse: "stored per person… not in local storage"). Message-area §09 defines a compact message stream too.
- **Shipped:** a Comfortable/Compact segmented control on the Appearance page, stamping `data-density="compact"` on `<html>`. It narrows the sidebar (`--space-row` 9px→4px; the 32px row floor holds) **and** the message stream (`--message-space` 1.33→0.8em, `--message-grouped-gap` 0.35→0.15em, `--content-padding-block` 0.66→0.4rem, per §09; the 14px type and 28px avatar floors hold). Persisted in `localStorage`, per device, mirroring the theme toggle and its pre-paint bootstrap.
- **Why:** a device-local preference matches the theme control already there and needs no model or endpoint. **Trade-off:** density doesn't follow you to a second device. (The message stream was originally scoped out; that decision was later reversed to match §09.)

## Sidebar collapse memory — localStorage vs. per-person preference
- **Handoff:** Favorites/Rooms/DMs remember their collapsed state per person, per community — a stored preference, "not in local storage".
- **Shipped:** remembered in `localStorage`, reusing the existing Favorites `collapsible-section` controller.
- **Why:** a server-persisted preference is a larger change; this matched the collapse behavior already shipped for Favorites. **Trade-off:** collapse state doesn't follow you to a second device.

## Sidebar — not yet built
Deferred spec work, not divergences — captured here so it isn't lost. Sizes are rough.

- **UNREAD section** (spec §02, §08) — a dedicated, always-open section that floats unstarred-unread rooms above ROOMS and vanishes at zero. Needs render-time bucketing plus unread-aware broadcast targeting (a room's section changes as it goes unread/read). _Large._
  - _First-load cost is ~flat._ Every sidebar render already computes `membership.unread?` per row (`_shared_link.html.erb`, `_direct.html.erb`, and the fragment-cache key in `sidebar_helper.rb`), and each call fires one `EXISTS` — `room.messages.after_cursor(...).exists?` — so the unread classification is already paid on every load. Bucketing must **partition the already-loaded `@shared_memberships` in Ruby** (`memberships.partition(&:unread?)`), reusing that value; it adds no queries. Do **not** implement it as two SQL passes (`shared.read` + `shared.unread`) — that re-runs the heavy correlated `UNSEEN_SQL` over the whole set twice per load on top of the per-row calls.
  - The "Large" weight is the **live re-bucketing**, not load time: today a read/unread flip only toggles a row's class over `ReadRoomsChannel`; with this section the row must move between two sections, so the broadcast payload + the client `rooms-list:unread`/`:read` handlers need to re-target.
  - Worth doing alongside: batch the per-row `unseen_messages?` `EXISTS` (an existing sidebar N+1) into one set-based query, since this section leans on it harder.
- **ROOMS cap at 8** (§02, §08, §10) — cap the read pool, keep the rest behind Browse, header count shows the true total. **Coupled to the UNREAD section** (must cap read rooms only, or it hides unread ones). _Medium._
- **Presence picker** (§07) — Available / Away / Do-not-disturb in the account menu (the only place presence is set). _Small–medium._

The spec's own unresolved questions (§11) also remain open by design: rail room ordering, whether forums get an unread count/dot, a DM row menu (mute/hide a conversation from the sidebar), and the mobile long-press affordance.
