---
date: 2026-07-06
topic: thread-forum-consistency-gaps
---

# Thread ↔ forum-post: behavioral consistency gaps (to evaluate)

## Summary

`Rooms::Thread` (chat thread) and `Rooms::Post` (forum post) are sibling sub-rooms —
both `Room::Participants`, both deriving access from a parent after the
thread-fanout branch. But they diverge in several **user-facing** ways: a forum
post behaves like a loud, controllable, room-like object; a chat thread behaves
like a quiet, implicit side-branch with no controls. Recorded for later
evaluation — **nothing decided, no work scheduled here.**

The theme: same underlying object, opposite notification/control profiles.

---

## Findings

### G1 — New activity lights the sidebar for forums, is silent for threads
- New **post**: lights the whole forum unread (a dot) for every member —
  `Message::Threadable#mark_forum_unread` → `Rooms::Forum#mark_unread_from_post`
  → `mark_members_unread`.
- New **thread**: no sidebar signal at all — only a reply-count bump on the parent
  message plus a notification to the thread's followers (the reply job drops the
  creator and also pulls in the parent room's `everything` subscribers). `threadable.rb`
  has no room-unread call for threads.
- **Read:** possibly a deliberate "threads = low-noise" choice. Confirm intent.

### G2 — @mention is louder in a forum than in a thread
- @mention in a **post**: Activity indicator **plus a number badge on the forum in
  the sidebar** (`Rooms::Forum#notify_mentioned_members` bumps
  `unread_notifications_count` + `UnreadNotificationsChannel`).
- @mention in a **thread**: Activity indicator **only, no sidebar badge**
  (`Message::Mentionee#create_mention_notifications` +
  `BroadcastMentionNotificationsJob` append to the Activity stream +
  `broadcast_activity_indicator`; `BroadcastMentioneeSidebarUpdatesJob` bails on
  non-sidebar rooms). `CreateThreadReplyNotificationsJob` handles the separate
  `thread_reply` fan-out and explicitly skips already-mentioned users.
- A thread mention can slip by with no red number anywhere in the sidebar —
  unlike a mention in a forum *or* a normal room, which both badge the sidebar.
  Threads are the odd one out.

### G3 — You can Unfollow a post, but not a thread (sharpest gap)
- Forum posts have an explicit **Follow / Unfollow control**
  (`app/views/rooms/forums/posts/_follow_control.html.erb`;
  `Rooms::Post#follow!` / `#unfollow!`).
- Chat threads have **no follow control**. You implicitly follow the moment you
  reply, and every visible thread member is notified of *every* subsequent reply
  (`CreateThreadReplyNotificationsJob` targets `memberships.active.visible`), with
  no button to turn it off. Reply once to an active thread → subscribed
  permanently.
- **Read:** this is a missing control, not a design stance — the forum side
  already solved it. Strongest candidate to fix.
- **Mute plumbing already exists.** The backend can already silence a thread
  follow — `Room#silence_thread_follows_for` flips involvement to `invisible`
  (via `ThreadFollowCleanupJob`) — but it only fires when you *leave the parent
  room*, never from a per-thread control. The mechanism is there; only the button
  is missing, so a thread Unfollow could reuse it rather than build new state.

### G4 — Replying sets a different follow level (internal; couples to G3)
- Reply to a **post** → membership `everything` (`Rooms::Post#follow!`).
- Reply to a **thread** → membership `mentions`
  (`Room#involve_user` uses `create_with(involvement: "mentions")`).
- No user-visible difference today (the reply-notification job notifies all
  *visible* members regardless of level), but inconsistent — and it would surface
  oddly the moment threads get a follow control (G3), which would read the level.

### G5 — Thread auto-follows the parent-message author; no forum analog
- Starting a thread on someone's message auto-subscribes that person
  (`Rooms::Thread.find_or_create_for` grants `[creator, parent_message.creator]`).
- A forum post has no equivalent — a post has no pre-existing author to subscribe.
  Structurally justified, but it widens the "who behaves how" gap between the two.

---

## Differences that are intentional (NOT gaps)

Recorded so we don't re-litigate them: Solved / accepted-answers (Q&A vs
chit-chat), post titles + permalinks + gallery layout, threads being reached via
their message vs forums being browsable/joinable from Browse, and `@everyone`
being unavailable in both sub-rooms (consistent between them, and sensible — a
side-conversation shouldn't page the whole community).

---

## Open questions for later

- Is the loud/quiet split (G1, G2) intentional, or should thread activity surface
  more like forum/room activity?
- G3 is the clearest fix: a thread follow/mute control reusing the
  `follow!` / `unfollow!` shape. Landing repliers at the same level as posts would
  also close G4 for free.
