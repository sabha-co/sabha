# Redesign v2 — performance regressions vs. `main`

A review of the `redesign-v2` branch (148 commits, merge-base `b0b5aa1`) for
runtime performance regressions relative to `main` — new N+1s, duplicated
queries, and heavier real-time broadcasts introduced by the redesign. Scope was
the runtime code (models, controllers, jobs, helpers, hot views, JS); tests,
CSS, and docs were excluded.

Findings were verified against the code, not inferred from the diff alone.

---

## TL;DR

No catastrophic regressions — nothing changes algorithmic order or blocks a
request. What the branch adds is a cluster of **view-layer N+1s and duplicated
queries on the new redesign surfaces** (threads inbox, roster panel, reactions),
all fixable with preloads / batching / memoization and no schema change. The JS
layer is clean.

| # | Severity | Surface | Regression | Fix shape | Status |
|---|----------|---------|------------|-----------|--------|
| 1 | **High** | Threads inbox | ~2 uncached queries per card (≈50/page) | preload + batch | ✅ fixed |
| 2 | **Medium** | Roster panel | 1 `user.badge` query per member, every desktop channel visit | one-line preload | ✅ fixed |
| 3 | **Medium** | Reactions broadcast | full uncached container re-broadcast per toggle | memoize + re-cache chip | ✅ fixed |
| 4 | Low | Threads inbox | accessible-thread subquery runs twice per visit | lighter count | ✅ fixed |
| 5 | Low | Activity feed | `room.parent_room` per sub-room row | preload | ✅ fixed |

Estimated total: ~half a day of preload/batch/memoize work. #1 and #2 are worth
doing before this ships.

**All five are now fixed**, each pinned with a query-count regression guard (see
"Suggested test guards" below). Notes on the fixes:

- **#1** — `Inbox::ThreadsQuery#call` now `.includes(threads: :creator)`, and a new
  `Inbox::ThreadsQuery.followed_thread_room_ids` batches follow state in one query
  (mirroring `unseen_reply_counts`), threaded into `_thread_card` →
  `_follow_control` via a `followed:` local that falls back to `followed_by?` for
  the single-render sites. The broadcast job passes the follow state it already
  knows (a visible thread member is exactly a follower), so the fan-out drops its
  per-recipient `followed_by?` too. Controller guard: `many - few` queries flat as
  cards triple (2 → 6).
- **#3** — `Message#boost_groups` is memoized; `Boost#broadcast_boosts` calls the
  new `Message#reset_boost_groups` first so the memo is fresh per toggle but shared
  across the toggle's two stream renders (memoizing naïvely served stale groups
  because `reload` does not clear plain ivars — caught by an existing test). The
  grouped chip (`messages/boosts/_boost`) is fragment-cached on `[message, content,
  count, boosters]`, so a toggle re-renders only the changed emoji's chip.
- **#4** — `@followed_thread_count` now calls a dedicated `Inbox::ThreadsQuery#count`
  that runs the accessible-parents subquery without `for_display`'s eager-load tree
  or the activity ordering.

---

## 1. HIGH — Threads inbox: ~2 uncached queries per card (≈50/page)

**Where:** `app/views/inboxes/threads/_thread_card.html.erb:14,26`
(via `app/views/inboxes/threads/_items.html.erb`)

**main vs. branch:** On `main` the Threads inbox rendered the `messages/message`
collection with per-row fragment caching (`cached: ->`), so warm loads issued
zero per-row queries. The branch renders the new **uncached** `_thread_card` in a
plain `.each`, and the card touches two associations that `Inbox::ThreadsQuery#call`
(`for_display`) does not preload:

- `thread.creator.name` — `for_display` preloads `:threads` but **not**
  `threads: :creator` → 1 query per card.
- `thread.followed_by?(Current.user)` inside `rooms/threads/_follow_control`
  (`Room::Followable#followed_by?`, an `exists?`) → 1 query per card.

**Magnitude:** at `PAGE_SIZE = 25`, ~50 uncached queries per load — on every
initial open and every scroll page of Activity › Threads, where `main` did zero
on a warm cache.

**Also hits the fan-out:** the same partial is rendered per-recipient by
`broadcast_inbox_threads_job`, so each first-reply broadcast issues one
`followed_by?` query per recipient. One fix covers both call sites.

**Fix:**
- Add `.includes(threads: :creator)` to `Inbox::ThreadsQuery#call`.
- Batch the follow state the way `Inbox::ThreadsQuery.unseen_reply_counts`
  already batches unread counts: compute a Set of followed thread-room ids in one
  query and pass it into the card / follow control, instead of a per-card
  `followed_by?`.
- Consider restoring a fragment cache on the card.

---

## 2. MEDIUM — Roster panel: one `user.badge` query per member

**Where:** `app/models/room/roster.rb:42`

**main vs. branch:** The roster panel is new on this branch. `Room::Roster#users_for`
preloads `avatar_attachment: :blob` but not `:badge`. Each `_member` row renders
`users/role_badge`, which reads `user.badge` → one query per member.

**Magnitude:** the panel **auto-loads on every non-DM, non-sub-room channel visit
on wide viewports (≥1280px)** via `thread_panel_controller#autoOpenRoster`
(fed by `content_for(:auto_panel_src)`). A channel with 30 present/away members
fires ~30 badge queries on essentially every open. Scales with concurrent
presence.

**Fix (one line):**
```ruby
.includes(:badge, avatar_attachment: :blob)
```

---

## 3. MEDIUM — Reactions: full uncached container re-broadcast per toggle

**Where:** `app/models/boost.rb` (`broadcast_boosts`),
`app/models/message.rb:169` (`boost_groups`)

**main vs. branch:** On `main`, a reaction **create** appended a single
fragment-cached avatar chip, and a **remove** broadcast a payload-free
`action: :remove` (no render, no query). The branch fires
`after_commit :broadcast_boosts` on **both** create and destroy, re-rendering the
**entire uncached** grouped container to **two** streams (the room stream and the
account-wide inbox stream).

The grouped-container-replace is the **intentional, owner-accepted** design — you
cannot append into an existing group, so a toggle replaces the whole chip row.
That part stays. Two costs ride along that are *not* intentional:

- **`boost_groups` is not memoized** (`message.rb:174` rebuilds
  `boosts.includes(:booster)` on each call), so the two broadcast renders issue
  the boosts+boosters SELECT twice per toggle instead of once (three times
  counting the create/destroy controller response).
- **Fragment caching was lost** — the grouped chip is no longer cached, so each
  toggle re-renders the whole row from scratch and pushes a ~20–40× larger
  payload on a hot message than main's single-chip append.

**Magnitude:** a message with ~30 reactions across ~8 emoji re-renders the full
~8-chip container (up to 5 avatars each, plus hidden forms and the add control)
on every single toggle, fanned to every present viewer of the room stream and
every client on the account-wide inbox stream. Reaction toggling is a
high-frequency path.

**Fix:**
- Memoize: `@boost_groups ||= …`.
- Restore a fragment cache on the grouped chip, keyed on booster ids + count.
- Optionally skip the redundant account-wide inbox re-render for reactions on
  messages the inbox is not showing.

---

## 4. LOW — Threads inbox: accessible-thread subquery runs twice per visit

**Where:** `app/controllers/inboxes/threads_controller.rb` (`@followed_thread_count`)

**main vs. branch:** `main` computed no count, so the heavy double-`EXISTS`
accessible-thread-parents subquery in `Inbox::ThreadsQuery` ran once per load. The
branch adds `@followed_thread_count = Inbox::ThreadsQuery.new(...).call.except(:order).count`
for a header badge, re-running the same subquery a second time. One extra heavy
query per visit (not per-row).

**Fix:** derive the badge from the already-loaded first page when not paginating,
or extract the accessible thread-parent id set into a reusable scope and count
from it directly (no `for_display`, no order machinery).

---

## 5. LOW — Activity feed: `room.parent_room` per sub-room row

**Where:** `app/helpers/notifications_helper.rb:33`

**main vs. branch:** The new `activity_room` helper reads `room.parent_room` for
sub-room (thread-reply) rows. `Notification.with_message_and_creator` preloads
`message: [:room, …]` but not `room.parent_room`, so each thread-reply row on the
uncached `_activity` partial fires a parent_room lookup. Modest — indexed PK
lookups, up to ~25/page — and `main` did comparable per-row room work (but
fragment-cached), so the net regression is small.

**Fix:** add `room: :parent_room` to the `with_message_and_creator` includes.

---

## Checked and cleared (not regressions)

- **Boost list rendering** — `for_display` preloads
  `boosts: { booster: … }`, so `boost_groups` groups in memory with no per-message
  N+1 on message-list pages; standalone renders batch boosters in one query.
- **DM rail / DM inbox presence** — batched via `@direct_member_statuses`; the
  per-conversation `activity_statuses_for` fallback is guarded to single-row live
  broadcast re-renders, not loops.
- **Browse rooms** — `@joined_room_ids` built once as a Set; `active_member_count`
  is a 5-minute cache, unchanged from `main`.
- **New pinning broadcast** (`Room::Pinning#broadcast_pin_change`) — net-new
  feature, staff-only, bounded; not a regression.
- **Sidebar frame** — gained ~4 bounded, non-N+1 queries per lazy load; none
  scale with a rendered collection. Minor nit (now fixed): it recomputed a member
  count on every render. Resolved by `User.member_count` — a single tenant-scoped
  5-minute cache now shared by the sidebar, the account-settings overview, the
  members directory, the signup page, and the SaaS workspace-settings page. All
  five had drifted apart (most excluded bots; the signup and SaaS pages included
  them, and the SaaS one also skipped the verified filter and the cache entirely);
  they now agree and exclude bots, matching the members list and the separate bots
  page. The tenant cache-key helper moved from `UsersController` to
  `ApplicationRecord.tenant_cache_key`. Two counts deliberately stay as they were:
  the "here now" / "online" counts (uncached — presence is live, and it's one cheap
  distinct count plus a per-user EXISTS per render), and `Workspace#refresh_snapshot!`'s
  `active_users` metric (`User.active.count` — a point-in-time usage snapshot, not a
  UI member count, so it must not be cached or filtered to verified humans).
- **JS** — clean. The per-message `reaction_bar` MutationObserver is
  `childList`-only, scoped to its own message, and disconnects cleanly (watch
  item only: idle observer count grows with scrollback length). `sidebar_filter`
  runs O(N) per keystroke with no debounce but does write-only DOM work (no
  interleaved reads, so no forced reflow) — fine at realistic sidebar sizes.
  `getComputedStyle` reads in `toggle_class` are gated behind a cheap class check
  on discrete pointer events. Nothing regresses vs. `main`.

---

## Suggested test guards

The redesign has no query-count assertions on these paths, so a fix can silently
regress. When fixing, pin each with an `assert_queries`-style guard:

- Threads inbox render (`Inboxes::ThreadsController#index`) — bounded queries
  regardless of card count.
- Roster panel (`Rooms::RostersController#show` / `Room::Roster`) — member badges
  batch-loaded.
- Boost create/destroy — bounded boosts/booster query count per toggle.
- Activity feed — no per-row `parent_room` query.
