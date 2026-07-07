# Plan: Close the thread ↔ forum-post consistency gaps

**Status:** proposed · **Date:** 2026-07-07 · **Branch:** TBD · **Ships as:** one PR

> Resolves the gaps recorded in `docs/brainstorms/2026-07-06-thread-forum-consistency-gaps.md`
> (G1–G5), verified against code on 2026-07-07. Decisions were made interactively; this plan
> encodes them.

> **Path note.** Bare filenames are shorthand: `threadable.rb` → `app/models/message/threadable.rb`;
> `rooms/forum.rb`, `rooms/post.rb`, `rooms/thread.rb` → `app/models/rooms/*.rb`; `room.rb` →
> `app/models/room.rb`; `involvable.rb` → `app/models/membership/involvable.rb`; `threads_controller.rb`
> → `app/controllers/rooms/threads_controller.rb`; `posts/memberships_controller.rb` →
> `app/controllers/rooms/posts/memberships_controller.rb`. All other cited paths are full.

## Goal

`Rooms::Thread` (chat thread) and `Rooms::Post` (forum post) are sibling sub-rooms that diverge in
user-facing notification and control behavior. This closes the divergence by making the two behave
consistently — **leveling notification loudness *down* (quiet forums to match threads) and adding the
missing thread control *up* (a follow/unfollow control to match posts).**

## Decisions (locked)

| Gap | Decision | Work |
|---|---|---|
| **G1** — thread activity is silent in the sidebar; forums light up | **Leave as-is.** Threads stay quiet on purpose — a thread lives inside a busy room; lighting the parent would conflate side-branch chatter with the main channel. | none |
| **G2** — @mention badges the sidebar in a forum, not in a thread | **Quiet the forum.** A forum mention should behave like a thread mention: Activity tab only, no sidebar dot or number. Normal rooms are unchanged — the new rule is "rooms are loud, sub-room containers are quiet." | remove `notify_mentioned_members` |
| **G3** — no Unfollow control for threads; posts have one | **Add it.** Mirror the post follow/unfollow control for threads. | new concern / route / controller / view |
| **G4** — thread reply → `mentions`; post reply → `everything` | **Align to `everything`.** Thread followers land at `everything` like posts; the new Unfollow (G3) is the escape hatch. | shared `follow!` |
| **G5** — thread auto-subscribes the parent-message author; no forum analog | **Keep, now opt-out-able.** The auto-subscribe (a courtesy: "someone threaded your message") stays; G3's Unfollow makes it dismissable. | none (falls out of G3) |

---

# Change 1 — Quiet the forum mention (G2)

Small, self-contained, independent of the thread work.

**`rooms/forum.rb`:**
- In `mark_unread_from_post` (`forum.rb:123`), drop the `notify_mentioned_members(message)` line. It
  reduces to: `mark_members_unread(message) if message.room.opening_message?(message)`.
- Delete the `notify_mentioned_members` private method (`forum.rb:151-161`).
- Update the `mark_unread_from_post` comment (it currently describes the mention path).

**Why this is the whole change.** `notify_mentioned_members` is the *only* place a forum touches
`unread_notifications_count` (`forum.rb:156`) or broadcasts `UnreadNotificationsChannel`. Removing it
means forum mentions produce no sidebar dot, no number badge, and no live badge broadcast.

**What is unaffected:**
- Mention **Notifications + Activity** are created by `Message::Mentionee#create_mention_notifications`
  — a separate path that never routed through `notify_mentioned_members`. Mentions still land in Activity.
- **New-post dot** (`mark_members_unread`) is separate and stays — forums still signal "something new here."
- **Normal rooms** keep their mention number badge (`Message::Unreadable#increment_unread_notifications_counters`,
  untouched).

**Side effect to note:** forum mentions will no longer contribute to the app/push badge total
(`Push::Subscription` counts `memberships.unread.where(unread_notifications_count > 0)`). Intended —
consistent with "quiet forums."

**Tests:** a forum mention no longer bumps `unread_notifications_count` and does not broadcast the badge;
it still creates the mention Notification / appears in Activity; a new post still lights the dot.

---

# Change 2 — Thread follow/unfollow control (G3 + G4 + G5)

One feature. Mirrors the post model so the two sub-room types become behaviorally identical for following.

## 2a. Extract the follow behavior into a shared concern

`follow!`, `unfollow!`, `followed_by?` on `Rooms::Post` (`post.rb:101-120`) are generic — nothing in
them is post-specific. Move them into a new `Room::Followable` concern.

- **New `app/models/room/followable.rb`:** holds `follow!` (activate + set `everything` when the row is
  new or `invisible`; never downgrades a follower who dialed themselves down), `unfollow!` (destroy the
  membership rows — access is parent-derived, so the row is pure subscription state), `followed_by?`
  (`memberships.active.where.not(involvement: :invisible).exists?`).
- **`rooms/post.rb`:** remove the three methods; `include Room::Followable`.
- **`rooms/thread.rb`:** `include Room::Followable`. Threads gain follow/unfollow for free at `everything`.

## 2b. Unify the sub-room follow-on-reply callback (closes G4)

`threadable.rb` currently has two parallel callbacks that diverge only in involvement level:

```ruby
after_create_commit :involve_creator_in_thread   # thread → involve_user → "mentions"
after_create_commit :follow_post_by_creator       # post   → follow!      → "everything"
```

Collapse into one:

```ruby
after_create_commit :follow_sub_room_by_creator
...
def follow_sub_room_by_creator
  room.follow!(creator) if room.sub_room?
end
```

**Net behavior change:** a third-party thread replier now lands at `everything` instead of `mentions`.
(The thread creator and parent-message author are already at `everything` via `Rooms::Thread#default_involvement`.)

**Verified safe — dropping the old `unread: false`:** `follow!` never touches `unread_at`, and
`Room#unread_memberships` already excludes the sender (`memberships.visible.disconnected.read.where.not(user: message.creator)`,
`room.rb:383`), so a replier's own reply never marks their membership unread. No-op.

## 2c. Stop subscribing on *open* — REQUIRED for Unfollow to persist

`threads_controller#create` (the "open/start a thread" action) currently runs:

```ruby
@room = Rooms::Thread.find_or_create_for(@parent_message, creator: Current.user)
@room.involve_user(Current.user, unread: false)   # ← subscribes the opener at "mentions"
```

**Remove the `involve_user` line.** This is not optional cleanup — it's load-bearing for G3. If opening a
thread re-subscribes you, then **Unfollow never sticks**: unfollow (destroy the row), navigate away,
re-open → `involve_user` re-creates the membership and you're followed again. Removing it makes the model
match posts exactly:

- **Create a thread** → creator + parent author followed at `everything` (via `find_or_create_for`'s
  `auto_followers`). Unchanged.
- **Reply** → follow at `everything` (2b). 
- **Open/lurk** → no membership, no subscription (a lurker on a thread == a lurker on a post).
- **Explicit Follow button** → subscribe without replying; **Unfollow** → and it persists across re-opens.

`show` is unaffected — `set_membership` only *loads* the current user's membership (nil for a lurker), and
`show.html.erb:20` already guards `turbo_stream_from @membership if @membership`.

> `involve_user`'s other two callers are untouched: the thread reply path (2b replaces it with `follow!`)
> and the bot cross-room post (`app/controllers/api/bots/messages_controller.rb:39`), which keeps its
> `mentions` default.

## 2d. Route + controller + view

- **`config/routes.rb`:** nest a membership resource under threads (mirrors posts at `routes.rb:161`):
  ```ruby
  resources :threads, only: %i[ create show edit update destroy ] do
    resource :membership, only: %i[ create destroy ], module: "threads"
  end
  ```
- **New `app/controllers/rooms/threads/memberships_controller.rb`:** mirror
  `Rooms::Posts::MembershipsController` — `create` → `follow!`, `destroy` → `unfollow!`, respond by
  replacing the follow frame via turbo_stream (or redirect fallback). Simpler than the post version: a
  thread has no gallery card, so it only flips the follow control frame. Access check: `viewable_by?`.
- **New `app/views/rooms/threads/_follow_control.html.erb`:** mirror
  `app/views/rooms/forums/posts/_follow_control.html.erb`, keyed on `dom_id(thread, :follow)`, using
  `rooms_thread_membership_path(thread)` for the Follow (POST) / Unfollow (DELETE) buttons.
- **`app/views/rooms/threads/show.html.erb`:** surface the control in `.thread-panel__header` (today it
  holds only the title + close button, `show.html.erb:3-11`). Render `rooms/threads/follow_control`.
  A full `⋯` options menu matching the post header (Copy link / Edit / Delete + Follow) is *optional
  polish* — out of scope unless we want it here.

## 2e. Comment fix

`app/models/message.rb:296` — the `:thread_reply` push comment says thread members are at `:mentions`
"by default." After 2b they're at `everything`. Update the comment; the logic (uses the `.visible` scope)
is already correct for either level, so no code change. Threads now match posts, which already run repliers
at `everything` through the same push path.

## Tests (mirror `test/controllers/rooms/posts/memberships_controller_test.rb`)

- Follow (POST) creates a membership at `everything`; Unfollow (DELETE) destroys it.
- `followed_by?` transitions across follow → unfollow → re-follow.
- A thread reply lands the replier at `everything` (not `mentions`).
- **Unfollow persists across re-open** — the regression 2c protects: unfollow, hit `create` again for the
  same thread, assert still not followed.
- Unfollow stops `CreateThreadReplyNotificationsJob` reaching that user (they leave `memberships.active.visible`).
- The parent-message author (G5 auto-subscribe) can Unfollow and it sticks.

---

## Out of scope

- G1 (thread sidebar activity) — deliberately unchanged.
- Forum-index per-post unread indication (per-visit watermark) — separately discussed, **parked**.
- A full `⋯` options menu on the thread panel header — polish, not required for the control.

## Blast radius

- **Change 1** touches one method on `Rooms::Forum`; the only consumers of the removed behavior are the
  forum sidebar badge (intentionally removed) and the push badge count (intentionally reduced).
- **Change 2** is additive except 2b/2c, which alter thread involvement level (`mentions → everything`) and
  remove subscribe-on-open. Both move threads onto the already-in-production post model — low novelty.
