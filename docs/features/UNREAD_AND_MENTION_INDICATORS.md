# Unread and mention indicators

How Sabha decides what "unread" markers a user sees — the sidebar dot, the red
count badge, and the Activity tab — and why the same event produces **different**
markers in a normal room, a forum, and a chat thread.

This is the *indicator* layer: what lights up and where. For the delivery layer
underneath it (who gets a push/email, the routing dispatcher, activity-type
vocabulary), see [`NOTIFICATIONS.md`](NOTIFICATIONS.md). For forum structure, see
[`FORUMS.md`](FORUMS.md).

---

## The signals

A user can see up to four "you have unread things" markers, each backed by a
different piece of state:

| Marker | Backed by | Means | Broadcast on |
|---|---|---|---|
| **Sidebar unread dot** | `membership.unread_at` (not null) | "something new happened in this room" | `UserUnreadRoomsChannel` (`forceUnread: true`) |
| **Sidebar count badge** (red number) | `membership.unread_notifications_count` (> 0) | "you have N unread things that notify you" (mentions, or every message in a DM) | `UnreadNotificationsChannel` |
| **Activity tab indicator** | `Notification` rows (`mention` / `thread_reply` / `boost`) | "you were named, or a thread you follow moved" | `broadcast_activity_indicator` + append to `[user, :inbox_activity]` |
| **App / push badge** | `memberships.unread.where("unread_notifications_count > 0").count` across **all** memberships | OS-level unread count | `Push::Subscription` |

Clearing all sidebar markers rides one channel — `ReadRoomsChannel` → the client's
`rooms_list#read` strips the unread and badge classes off the sidebar entry.

Threads also drive a fifth, in-context marker: the **reply count on the parent
message** ticks up live (`Message::Threadable#update_thread_reply_count`).

---

## The axis that explains everything: does the room have a sidebar entry?

The dot and the count badge attach to a **sidebar entry**. Only some room types
have one:

```ruby
# app/models/room.rb
def sidebar_room? = open? || closed? || forum?   # + Direct, rendered in the DM list
def sub_room?     = thread? || post?             # NO sidebar entry of their own
```

- **Open / Closed / Direct / Forum** are sidebar rooms → they can show a dot and a
  count badge.
- **Threads and posts are sub-rooms.** They have no sidebar entry, so they can
  never show a dot or count there. Their only "unread" surface is the **Activity
  tab** (plus, for threads, the parent message's reply count, and the push badge
  via their own membership row).

A forum is a sidebar room but **owns no messages** — its posts do. So a forum's
dot is an *aggregate* poked by post activity, not its own message stream
(`Rooms::Forum#receive` is a no-op).

---

## Behavior matrix

What each event lights up, per room type:

| Event | Open / Closed room | Direct message | Forum | Chat thread |
|---|---|---|---|---|
| **New content** | sidebar **dot** | **dot + count** (DMs count every message) | new **post** → forum **dot**; a **reply** → nothing in the sidebar | nothing in the sidebar; parent-message reply count ticks up; followers get an **Activity** row |
| **@mention of you** | **dot + count** + **Activity** row | (already counted every message; no separate mention row) | **Activity** row only — **no** forum dot or count | **Activity** row only — no sidebar marker |
| **@everyone** | dot + count (all members) + Activity | — | unavailable | unavailable |
| **Clears when** | you open the room, or read Activity | you open the DM | you open the forum gallery | you open the thread panel, or read Activity |

The row that surprises people: **a mention is quieter in a forum or a thread than
in a normal room.** In a room, an `@you` badges the sidebar with a red number. In
a forum or a thread it does not — it reaches you only through the Activity tab.
Normal rooms are the loud tier; forums and threads are the quiet tier. (A new
*post* still lights the forum's dot — that's ambient "something new here," not a
mention badge.)

---

## How the markers get SET

Everything fires from `after_create_commit` callbacks when a `Message` is created.

**`Message::Unreadable`** — the dot and the count, for the message's own room:

- `deliver_to_room` → `room.receive(message)` → (base `Room#unread_memberships`)
  sets `unread_at` on `memberships.visible.disconnected.read` **except the sender**
  → **dot**. `Rooms::Forum#receive` overrides this to a no-op (a forum owns no
  messages).
- `increment_unread_notifications_counters` → bumps `unread_notifications_count`
  → **count badge**. Recipients:
  - **DM** → every member (a DM counts every message);
  - **`@everyone`** → all members minus the sender;
  - otherwise → the named mentionees minus the sender;
  - a plain message with no mention bumps no one.

**`Message::Mentionee`** — the Activity row for an `@mention`:

- `create_mention_notifications` inserts `Notification(activity_type: "mention")`
  and calls `broadcast_activity_indicator`. Skipped for events and for DMs
  (`return if room.direct? || room.parent_room&.direct?` — a DM already notifies
  on every message, so a mention needs no separate row).

**`Message::Threadable`** — sub-room aggregation into the forum, and thread/post
follow notifications:

- `mark_forum_unread` → `Rooms::Forum#mark_unread_from_post` → `mark_members_unread`
  **only for a post's opening message** → the forum **dot**. A forum **@mention**
  is deliberately *not* surfaced here — it reaches the member through Activity
  only, like a thread mention.
- `create_thread_reply_notifications` → `CreateThreadReplyNotificationsJob` →
  `Notification(activity_type: "thread_reply")` for the sub-room's followers
  (`memberships.active.visible`) plus the container's `involved_in_everything`
  members, minus the creator and anyone already sent a mention row → **Activity**.
- `update_thread_reply_count` → live reply count on the parent message.

---

## How the markers CLEAR

**Opening the room clears its dot and count** — via presence. The `presence`
Stimulus controller subscribes to `PresenceChannel`; on subscribe the server runs
`Membership#present` → `Connectable.connect` sets `unread_at: nil,
unread_notifications_count: 0` and broadcasts `ReadRoomsChannel`. The client then
strips the markers off the sidebar entry.

The `presence` controller is mounted by:
- `message_area_tag` — normal room streams **and** the thread panel;
- the **forum gallery** container directly (it renders cards, not a message
  stream, so it wires presence itself).

**Reading the Activity tab / inbox** clears notification counts and marks notified
rooms read — `User#mark_inbox_as_read` → `Membership#read_until`, which recomputes
`unread_notifications_count` and broadcasts `ReadRoomsChannel` for rooms that go
fully read.

---

## Subtleties worth knowing

- **DMs count everything.** A DM's badge counts every message, not just mentions —
  so a DM mention needs no separate mention row (it's already covered).
- **Sub-rooms and the push badge.** Threads and posts show nothing in the sidebar,
  but their own membership row still carries `unread_at` / `unread_notifications_count`,
  and the push badge counts **all** memberships. So a mention in a thread you
  already follow can still tick the OS app-icon badge, even with no sidebar marker.
  A forum, by contrast, never bumps its own count (its mention path was removed),
  so forum mentions don't contribute to the push badge.
- **`@everyone` is hidden outside Open rooms — as a UI gate.** The compose picker
  offers it only to admins in Open rooms (`Autocompletable::UsersController`), so
  it isn't suggested in forums, posts, or threads. This is UI-only, though: the
  `mentions_everyone` flag is computed from the message body, so a pasted mention
  or a bot could still set it in those rooms — there's no server-side guard today.
- **Sub-rooms under a DM stay quiet.** A thread or post whose container is a DM
  produces no mention/thread_reply rows (`create_thread_reply_notifications` and
  the mention path both bail on a direct parent) — the DM's own every-message
  counting already covers it.

---

## Code map

**Setting markers**
- `app/models/message/unreadable.rb` — dot (`deliver_to_room`) + count (`increment_unread_notifications_counters`)
- `app/models/message/mentionee.rb` — mention Activity rows
- `app/models/message/threadable.rb` — forum-dot aggregation, thread/post reply notifications, parent reply count
- `app/models/rooms/forum.rb` — `mark_unread_from_post` / `mark_members_unread`
- `app/jobs/create_thread_reply_notifications_job.rb` — `thread_reply` recipient set

**Membership state + broadcasts**
- `app/models/membership.rb` — `unread_at`, `unread_notifications_count`, `read`/`read_until`/`mark_unread_at`, `broadcast_unread`/`broadcast_read`
- `app/models/membership/connectable.rb` — `connect` (clear-on-presence)
- `app/models/room.rb` — `sidebar_room?`, `sub_room?`, `receive`, `unread_memberships`

**Channels**
- `UserUnreadRoomsChannel` (dot) · `UnreadNotificationsChannel` (count) · `ReadRoomsChannel` (clear) · `PresenceChannel` (open/close → clear)

**Client**
- `app/javascript/controllers/rooms_list_controller.js` — `#unread` (adds dot/badge), `read` (removes them)
- `app/javascript/controllers/presence_controller.js` — subscribes on mount
- `app/javascript/controllers/read_rooms_controller.js` — clear signal

**Push badge**
- `app/models/push/subscription.rb` — counts unread memberships with a positive notification count
