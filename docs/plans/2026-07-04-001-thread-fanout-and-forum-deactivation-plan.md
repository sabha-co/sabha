# Plan: Generalize derived access to chat threads, and move forum (de)activation to a batched background job

**Status:** proposed · **Date:** 2026-07-04 · **Branch:** TBD (follow-up, after `feat/forum-rooms` merges)

> **Two sequenced follow-ups from the forum work**, both recorded in `docs/plans/2026-07-03-001-rooms-post-model-plan.md` § Follow-ups. **Part A** applies the post access model (derived access + no membership fan-out) to `Rooms::Thread`. **Part B** moves the forum-delete cascade off the request path into a batched background job. Part A ships first: it shrinks the membership footprint that Part B's cascade has to undo, and it's the higher-risk change (live production data), so it gets its own review cycle.

> **Path note (claims verified against code 2026-07-04 — line numbers accurate).** Bare filenames below are shorthand; full paths: `involvable.rb` → `app/models/membership/involvable.rb`; `threadable.rb` → `app/models/message/threadable.rb`; `mentionee.rb` → `app/models/message/mentionee.rb`; `nested.rb` (`Room::Nested`) → `app/models/room/nested.rb`; `message_pusher.rb` → `app/models/room/message_pusher.rb`; `threads_controller.rb` → `app/controllers/rooms/threads_controller.rb`; `notification_settings_controller.rb` → `app/controllers/users/notification_settings_controller.rb`; `Inbox::ThreadsQuery` → `app/models/inbox/threads_query.rb`. All other cited paths (`room.rb`, `rooms/forum.rb`, `rooms/post.rb`, `rooms/thread.rb`, the job/mailer/view paths) are correct as written.

## Goal

Two scale ceilings the forum feature deliberately left standing:

1. **Chat-thread membership fan-out.** Creating a thread writes a membership row for *every* active member of the parent room (`threads_controller.rb:10` passes `users: parent_room.users`), and `Room#memberships.grant_to`/`revoke_from` cascade every room join/leave into every thread (`room.rb:13`, `room.rb:24`) — mostly `involvement: "invisible"`. Membership rows scale as **(room members × threads)**. Posts removed this for themselves; threads still carry it.
2. **Synchronous forum deactivation.** Deleting a forum soft-deletes every post and every reply in **one request-thread transaction** — O(posts × (participants + replies)) `update_all`s (`room.rb:deactivate` → `deactivate_threads` → `Room::Nested#deactivate`). A large forum times out the request and holds a long write lock.

## Why this is well-de-risked

Part A is **not** new design — it's generalizing the D2 model that posts already run in production behind this branch. Several load-bearing pieces already exist:

- **The inbox already derives *a* parent-room predicate — proof the pattern works, but not the predicate T1 needs.** `Inbox::ThreadsQuery#accessible_thread_parent_ids_sql` surfaces a thread when the user has a visible thread membership **OR** `involvement: "everything"` in the parent room (`inbox/threads_query.rb:32-48`), and `BroadcastInboxThreadsJob` unions the same two sets. But that is the **narrow "should this thread show in your inbox"** question (actively involved) — **not** T1's **broad "can this user open the thread"** question (any active member). The two must not be conflated: the precedent proves parent-derivation is feasible, it is **not** a drop-in for the view gate. See the ⚠️ in A2.
- **Threads already create membership lazily on engagement.** `Message::Threadable#involve_creator_in_thread` involves the poster on every thread message (`threadable.rb:15`). Unlike posts (which had to *add* `follow!`), threads only need the **two fan-out sites removed** and **derived access added** — the per-reply path stays.
- **The controller/model surface to generalize is exactly what posts touched.** `set_room` fallback, `User#reachable_message`, `Autocompletable::UsersController`, `Message::Mentionee#mention_roster` all special-case `post?` today; each becomes `post? || thread?` (or a shared `sub_room?` predicate).

## Key difference from the post refactor — and the real risk

Posts were **greenfield** (no production data, local posts reseeded). Threads are **live**: production holds fanned-out `invisible` thread rows, and threads have more consumers (inbox threads, activity feed, reply notifications, the thread panel). So Part A is **characterization-first**: capture current access/unread/inbox/notification behavior before touching anything, then refactor to hold those behaviors.

---

# Part 0 — Companion fix: posting must not silently unmute

Independent of the fan-out work, this is a pre-existing bug in shared involvement code, surfaced by T3's verification and small enough to ship first.

**Bug.** `ensure_receives_mentions!` (`involvable.rb:27-28`) is `update(involvement: :mentions) unless receives_mentions?` with `receives_mentions? == mentions || everything`. It therefore lifts **both** `invisible` *and* `nothing` up to `mentions`. But `nothing` is an **explicit mute** — it renders the bell-off indicator (`users/sidebars/rooms/_shared_link.html.erb:9`) and the notification-settings screen partitions it as "muted" (`notification_settings_controller.rb:36`). So a member who deliberately muted a thread/room and then posts in it is **silently un-muted** — the bell-off vanishes with no user action.

**Fix.** Lift only the *not-involved* default, never an explicit choice:

```ruby
def ensure_receives_mentions!
  update(involvement: :mentions) if involved_in_invisible?
end
```

> `involved_in_invisible?` is the enum predicate auto-generated by `enum :involvement, ..., prefix: :involved_in` (values `invisible, nothing, mentions, everything`). It's a discrete predicate check, so the fix is correct independent of the enum's integer ordering — don't reason about "below mentions" by numeric comparison (`invisible` = 0, `nothing` = 1, so a `< :mentions` test would wrongly catch the explicit mute).

**Blast radius — confirmed safe.** `ensure_receives_mentions!` has a **single caller**, `Room#involve_user` (`room.rb:108`), reached only from three *poster-involvement* sites (thread reply `threadable.rb:16`, thread create `threads_controller.rb:11`, bot cross-room post `api/bots/messages_controller.rb:43`). **Mention delivery is unaffected** — `@mention` notifications are inserted directly by `Message::Mentionee#create_mention_notifications`, which never routes through `involve_user`. So respecting `nothing` changes only the poster's *own* notification level, not who receives mentions.

**Test.** A `nothing`-muted member who posts stays `nothing` (mute survives); an `invisible` member who posts still rises to `mentions` (participation still pulls them in).

**Sequencing.** Ships **first** — one line, orthogonal, and it makes T3's "an existing follower's involvement is never rewritten" guarantee exact by deleting the one exception (`nothing → mentions`).

---

# Part A — Derived access + no fan-out for `Rooms::Thread`

## Decisions to lock

| # | Decision | Recommendation |
|---|----------|----------------|
| T1 | Thread access | **Derive from the parent room.** Lift a default `Room#viewable_by?(user)` = `memberships.active.exists?(user_id: user.id)` (Open/Closed use it as-is; `Rooms::Forum` already has this shape). `Rooms::Thread#viewable_by?` = `delegate :viewable_by?, to: :parent_room` — its parent is the Open/Closed room it was spawned in (`parent_room` denormalized FK). Exactly the post→forum delegation, one level over. **Two distinct `parent_room` associations exist** — `Room#parent_room` (`room.rb:46`, `class_name: "Room"`, thread → Open/Closed container) and `Rooms::Post#parent_room` (`rooms/post.rb:13`, `class_name: "Rooms::Forum"`). The thread delegation lands on the **base** `Room#parent_room`, which has **no `viewable_by?` today** (only `Rooms::Forum` defines one, `Rooms::Post` delegates to it) — so lifting the default `Room#viewable_by?` is load-bearing, not just tidy-up. |
| T2 | Remove the two fan-out sites | (a) `Rooms::Thread.find_or_create_for(parent_message, users:)` grants **the thread creator and the parent-message author** (`[ creator, parent_message.creator ].uniq`), not `parent_room.users`. Both auto-follow at `"everything"` (see `#default_involvement`) so the author hears about a thread opened on their message even when someone else opens it — verified deliberate in testing, not a full fan-out. (b) Delete the thread cascade in `Room#memberships.grant_to`/`revoke_from` (`room.rb:13`, `room.rb:24`). Posts got (b) "for free" by leaving `has_many :threads, through: :messages`; threads *are* that association, so it must be removed explicitly. |
| T3 | Lazy membership + involvement | **Keep today's semantics, just stop pre-creating rows.** `involve_creator_in_thread` already lazy-creates the poster's row. The safety is in two lines, verified: in `involve_user` (`room.rb:106-108`) `create_with(involvement: "mentions")` applies **only on insert** (an existing `"everything"` follower is left alone), and `ensure_receives_mentions!` (`involvable.rb:27-28`) is `update(:mentions) unless receives_mentions?` with `receives_mentions? == mentions \|\| everything` — so it can **only raise a below-mentions row (`invisible`/`nothing`) up to `mentions`** and is a **no-op on `mentions`/`everything`**. An existing follower's involvement is never rewritten ⇒ the reply-notification target set is unchanged. **Net effect of the refactor:** the poster's row is created lazily *at `mentions` on first post* instead of *pre-created at `invisible` then raised* — identical end state. The one exception, `nothing → mentions`, is **removed by Part 0** (ships first), which makes this guarantee exact. |
| T4 | Stale-row access defense | `set_room` (RoomsController **and** MessagesController) must **re-check `viewable_by?`** for threads even when a membership resolved the room — so a vestigial fanned row (or a row left behind after someone leaves the parent room) can't grant access. This is the post P1 gate generalized to threads. |
| T5 | Leave-cleanup | Leaving the parent room removes access for free (derived), but a lazy row for a thread you posted in stays active and keeps sending reply notifications. Mirror forums: on `Room#remove_member!` / `Membership#leave!` for Open/Closed rooms, enqueue a job that **silences that member's thread follows** (set their thread memberships in that room to `invisible`), scoped to the leaver. Mirrors `ForumFollowCleanupJob`/`silence_post_follows_for`. |
| T6 | Existing production rows | **Leave the fanned `invisible` rows inert; do not backfill/delete.** They're already excluded from the inbox query, and T4's `viewable_by?` re-check means a stale row can no longer grant access to a non-member. A one-time reclaim job (delete `invisible` thread memberships) is **optional cleanup**, not correctness — defer it. |
| T7 | `parent_room` accessor consistency | **Prefer the unified `parent_room` container FK over `parent_message.room` hops.** The association already exists on `Room` (`room.rb:46`) and is the dominant idiom (~20 call sites); a handful of leftover message-hops predate it and read as if `parent_room_id` were a bolted-on perf column rather than the primary "container" link. Sweep the pure aliases so the container concept reads as primary. Purely cosmetic — no behavior change, no migration. Rides this branch because A2/A4 already edit these files. |

## Phases

Ships on one branch; phases are in review order.

### A1 — Characterization tests (before any change)
- Pin current behavior with tests that must stay green: a parent-room member can open a thread they never posted in; a thread reply notifies the right people; inbox threads lists the right threads; leaving the room removes thread access + stops notifications; unread badges (threads drive none — confirm). These are the regression net for A2–A5.

### A2 — Derived access
- `Room#viewable_by?` default (member check); `Rooms::Thread#viewable_by?` delegates to `parent_room`.
- **⚠️ Do not reuse `Inbox::ThreadsQuery`'s SQL as this access check.** Its `involvement = 'everything'` clause is the narrow inbox-surfacing predicate; the view gate is *any active parent membership*. Reusing it would make threads unopenable for the `"mentions"`/`"invisible"` parent members who are entitled to read them. `viewable_by?` and inbox-surfacing stay two separate predicates.
- Generalize `set_room` in RoomsController + MessagesController: fall back to a viewable sub-room (thread **or** post) and re-check `viewable_by?` even when a membership resolved it (T4). Rename `viewable_forum_post` → `viewable_sub_room` (covers both).
  - **Not symmetric today:** the `viewable_forum_post` helper exists only in `MessagesController` (`:71`) and `Autocompletable::UsersController` (`:30`); `RoomsController#set_room` (`:45`) **inlines** the re-check with no helper. Both gate on `is_a?(Rooms::Post)`, **not** a `post?` predicate. So this phase = add a shared `sub_room?` predicate, generalize the inline `RoomsController` check, and rename the helper in the other two.
- Push derived reach down to the collection, not just the singular finder: `Message.reachable_by(user)` returns active messages in rooms the user belongs to **plus** sub-rooms whose *parent* they belong to. `User#reachable_messages` delegates to it and `reachable_message` becomes a plain `find_by || raise` — so search, unreads, the inbox feed, and the bots search API all get derived access uniformly. This both closes the stale-row leak (a silenced row left after leaving the parent fails the parent check) and fixes the passive-member under-reach (a parent member reaches a sub-room they never joined). The bots room resolvers (`Current.user.rooms.find`) get the same stale re-check via a shared `reachable_bot_room`.

### A3 — Stop the fan-out (T2)
- `find_or_create_for` grants the thread creator and the parent-message author (both auto-follow); no wider fan-out.
- Remove `room.rb:13` / `room.rb:24` thread cascades in `grant_to`/`revoke_from`.
- Confirm A1 characterization tests still pass (access now derived, not fanned).

### A4 — Generalize the mention/autocomplete surface
- `Autocompletable::UsersController#mentionable_users`: `thread?` → `parent_room.users` (already does this for posts).
- `Message::Mentionee#mention_roster`: `thread?` → `parent_room.users`. (Thread mentions already resolved via `room.users` = fanned members; after A3 those rows are gone, so this must switch to the parent-room roster or non-poster members become un-mentionable — the same bug we fixed for posts.)

### A5 — Leave-cleanup job (T5)
- `ThreadFollowCleanupJob` (or generalize `ForumFollowCleanupJob` to any container): on parent-room leave/remove, silence the leaver's thread follows in that room.

### A6 — (Optional) reclaim job (T6)
- One-time, batched delete of `invisible` thread memberships to reclaim rows. Log the count. Ship separately or skip.

### A7 — `parent_room` accessor consistency sweep (T7 — no behavior change)
Opportunistic; rides this branch because A2/A4 already touch several of these files. Replace `parent_message.room` with the unified `parent_room` accessor at the sites that are **pure aliases** (they don't otherwise need `parent_message`):
- `create_thread_reply_notifications_job.rb:63` — line **61** of the same file already uses `parent_room`; this removes the intra-file split.
- `broadcast_inbox_threads_job.rb:13` → `parent_room.memberships`
- `missed_notifications_mailer.rb:24` → `parent_room&.name`
- `threadable.rb:43` (broadcast target) → `parent_room`

**Explicitly leave the permalink hops alone** — `rooms_controller.rb:18`, `threads_controller.rb:28/33/46`, `message_pusher.rb:49` all build `room_at_message_path(room, message)` and need the *message*, so swapping `.room` saves nothing; likewise `Rooms::Thread.find_or_create_for` (`thread.rb:15`) runs before the thread object exists and must read `parent_message.room`.

**Also left as-is: `Room#display_name` (`room.rb`, the thread branch).** It reads `parent_message&.room&.name`, and swapping it to `parent_room&.name` would require repointing its sidebar/inbox `includes(parent_message: :room)` preloads to `includes(:parent_room)` to avoid trading a loaded association for an N+1. The churn across those call sites isn't worth a cosmetic swap, so this one site keeps the message-hop.

Guard so this stays a no-op:
- **All threads resolve.** `parent_room` is set on create — for threads via the `Rooms::Thread`-only `assign_parent_room` callback (`rooms/thread.rb:12`/`:37`, `before_validation ... on: :create`), for posts via `Rooms::Post.create!(parent_room: self)` (`rooms/forum.rb:35`) — and backfilled for existing rows (migration `20260703120000`), so no new `nil` paths.

## Part A risks
- **More consumers than posts.** Activity feed, reply notifications, thread panel all read thread memberships. A1's characterization net is the mitigation — do not skip it.
- **Open vs Closed parent semantics.** A thread's parent can be either; both gate on active membership, so the delegation is uniform — but verify auto-join Open rooms behave (membership exists after auto-join, so derived access holds).
- **`involve_user` involvement drift.** T3 keeps `"mentions"` for repliers; changing it would alter who the reply-notification job targets. Hold it fixed.

---

# Part B — Forum (de)activation as a batched background job

## Decisions to lock

| # | Decision | Recommendation |
|---|----------|----------------|
| F1 | Approach | **Plain batched, idempotent job — _not_ `ActiveJob::Continuable`.** Continuable is new in Rails 8.2 and its checkpoint/resume state has to round-trip the tenant context through `activerecord-tenanted`'s per-tenant DB switching — untested, and a resume that restores the wrong tenant is a severe failure mode on a destructive cascade. Skip it for now. `ForumDeactivationJob` iterates `Rooms::Post.where(parent_room_id:)` in **batches, committing per batch** — short transactions that release the SQLite single-writer lock between batches (this is what actually fixes the long-lock, independent of resume). Idempotent (re-soft-deleting a deleted row is a no-op), so an ordinary Solid Queue **retry re-runs from the start safely** — it re-does completed batches as no-ops rather than resuming from a checkpoint. The `forum_deactivated_at` gate-at-read alternative is also rejected: it broadens every post query and tangles with the `cascade_deactivated`/R15 restore marker. **Later upgrade:** revisit Continuable once the tenanted round-trip is proven, if wasted-work-on-retry ever matters. |
| F2 | Instant cutoff vs heavy cascade | **Split them.** Synchronously deactivate the forum row **and its own memberships** (one `update_all`, O(members)) so `viewable_by?` fails immediately and it leaves the sidebar. Enqueue the job for the expensive part — soft-deleting each post's messages, memberships, notifications (O(posts × replies)). Access is cut on click; row-cleanup is background. |
| F3 | Reactivation symmetry | **Mirror F2 in _both_ halves.** Synchronously reactivate the forum row **+ its own memberships** so it reappears in the sidebar and `viewable_by?` passes immediately; then route the O(posts × replies) post restore through the **same job with a direction** (or a sibling `ForumReactivationJob`). Only cascade-deactivated posts are restored (R15). Without the sync half, the forum "returns" but stays invisible to members until the async batch finishes. |
| F4 | Concurrency + retry | Guard against reactivate-during-deactivate: a `deactivating`/`reactivating` state on the forum (or a job-uniqueness lock) so the two can't interleave; every batch is idempotent (re-running a soft-delete is a no-op), so a Solid Queue retry after a crash is safe. |

## Phases

### B1 — Instant access cutoff (F2)
- `Rooms::Forum#deactivate` (override): deactivate the forum + its memberships synchronously, set the cascade marker path up, enqueue `ForumDeactivationJob`. Verify `Rooms::Post#viewable_by?` returns false the instant the forum's memberships are inactive (delegates to `parent_room.viewable_by?`), backed by the T4 `set_room` re-check.

### B2 — The job (F1)
- `ForumDeactivationJob` (plain `ApplicationJob`): iterate `Rooms::Post.where(parent_room_id:)` in batches, **committing each batch** (short transactions release the write lock); per post soft-delete messages + memberships + notifications (reuse `Room::Nested#deactivate`'s body); idempotent so a retry re-runs from the start harmlessly. No `Continuable` (F1). Test-first (unlike Part A) — it's a new mechanism, not a behavior we're preserving.

### B3 — Reactivation symmetry (F3)
- **Sync mirror of F2 first:** reactivate the forum row **+ its own memberships** synchronously, so it reappears in the sidebar and `viewable_by?` passes immediately — otherwise the forum "comes back" but stays invisible to members until the async batch finishes.
- Then the batched **post** restore (same job, restore direction); restore only `cascade_deactivated: true` posts (R15).

### B4 — Concurrency guard (F4)
- Forum (de)activation state + idempotent batches; test crash-and-retry (re-runs from start as no-ops) and reactivate-during-deactivate.

## Part B notes
- The cascade already reads `Rooms::Post.where(parent_room_id:)` (the D6 repoint the old plan flagged is **already done** in the merged feature — one less thing). Today it lives in the base `Room#deactivate_threads` (`room.rb:357-366`, forum-guarded), folded in alongside the thread cascade — there is **no** `Rooms::Forum#deactivate` override and **no** separate `deactivate_posts` method. So B1's `Rooms::Forum#deactivate` override is genuinely new code, not a replacement; it must peel the post branch out of `deactivate_threads` into the job.
- After Part A, the `× members` term in the cascade is already `× participants` (lazy memberships), so B's remaining cost is dominated by the `× replies` message soft-delete — which is exactly what the job batches.

---

## Sequencing & testing posture

- **0 → A → B.** Part 0 (the mute fix) ships first — one line, orthogonal, and it makes T3's guarantee exact. Then A before B: A shrinks the membership rows B must cascade, and A is the riskier (live-data) change, so it bakes first.
- **Part 0 is test-first** (a defined bug fix). **A is characterization-first** (preserve live behavior). **B is test-first** (new mechanism).
- Run both suites (self-hosted + SaaS model) at each phase; the tenant-scoped broadcasts and `activerecord-tenanted` per-workspace DBs are unaffected by either part, but the job (B) must be verified under SaaS tenancy (jobs run in a tenant context).
- **SaaS constraint (F1):** the Part B job stays a plain batched job — `ActiveJob::Continuable`'s checkpoint/resume is not trusted against `activerecord-tenanted`'s per-tenant DB switching yet. Correctness comes from per-batch commits (short write locks) + idempotency (safe retry), not from resume.

## Scope boundaries (non-goals)
- No change to thread/post **UI**, routes, or the reply/notification *content* — this is a membership/access + lifecycle-mechanics refactor only.
- No accepted-answer or public/SEO work.
- The per-reply participant-aggregate denormalization (the third recorded follow-up) is **out of scope** here.
