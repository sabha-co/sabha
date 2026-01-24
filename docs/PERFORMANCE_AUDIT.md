# Performance Audit: Campfire-CE at Scale

**Date:** 2026-01-23 (Updated: 2026-01-24)
**Target Scale:** Thousands of messages/day, hundreds of active users daily
**Status:** In Progress (3 of 4 Critical Issues Fixed)

---

## Executive Summary

This audit identifies performance bottlenecks that will impact Campfire-CE at scale. Issues are categorized by severity and include specific file locations, code samples, and recommended fixes.

**Critical issues requiring immediate attention:**
- N+1 queries in broadcast operations blocking message creation
- Thundering herd on global WebSocket channels
- Missing database indexes on frequently-queried columns

---

## Issue Tracking

### Legend

| Status | Meaning |
|--------|---------|
| 🔴 | Not started |
| 🟡 | In progress |
| 🟢 | Complete |
| ⏸️ | Deferred |

---

## 1. Critical Issues

### CRIT-1: O(n) Broadcasts + Heavy Preload in `broadcast_to_inbox_threads`

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P0 - Critical |
| **Impact** | High - blocks message creation |
| **Effort** | Low |
| **File** | `app/models/message/broadcasts.rb:74-84` |

**User Experience:**

You post a reply in a thread. Everyone following that thread needs to see the update in their Inbox → Threads tab. If 100 people are in the thread, 100 Turbo Stream broadcasts fire.

- **Before:** All 100 broadcasts happened inline. Your "Post" button felt slow because your request waited for all broadcasts to complete.
- **After:** Your message posts instantly. Broadcasts happen in a background job (`BroadcastInboxThreadsJob`). Other users see the thread update a moment later.

**Problem:**

Message creation is blocked while broadcasting individually to each thread subscriber. The method uses two `pluck`s and a single batched `User.where`, so it's not N+1 queries, but it still performs O(n) broadcasts and preloads a heavy `parent_message_with_threads` for each message.

```ruby
# Current implementation (simplified but accurate to behavior)
def broadcast_to_inbox_threads
  thread_user_ids = thread.memberships.active.visible.pluck(:user_id)
  parent_room_user_ids = parent_message.room.memberships.active.involved_in_everything.pluck(:user_id)
  all_user_ids = (thread_user_ids + parent_room_user_ids).uniq - [ creator_id ]

  users_by_id = User.where(id: all_user_ids).index_by(&:id)
  parent_message_with_threads = Message.includes(threads: { messages: { creator: :avatar_attachment } })
                                       .find(parent_message.id)

  all_user_ids.each do |user_id|
    # Individual broadcast per user - O(n) broadcasts
    user = users_by_id[user_id]
    next unless user
    broadcast_append_to user, :inbox_threads, ...
  end
end
```

**Impact at Scale:**
- Room with 100 thread watchers: 100+ broadcasts per message
- Expected latency: 200-500ms added to message creation
- With 50 active threads: potential for 5,000 broadcasts per popular message

**Recommended Fix:**

```ruby
def broadcast_to_inbox_threads
  return unless room.thread? && room.parent_message

  BroadcastInboxThreadsJob.perform_later(
    thread_id: room.id,
    parent_message_id: room.parent_message_id,
    message_id: id,
    creator_id: creator_id
  )
end
```

**Acceptance Criteria:**
- [x] Create `BroadcastInboxThreadsJob`
- [x] Move broadcast logic to background job
- [x] Add job tests
- [x] Verify message creation latency < 50ms (benchmarked: ~37-49ms avg, constant regardless of member count)

---

### CRIT-2: `RoomUpdateBroadcastJob` Per-Membership Broadcasts (Partial is User-Specific)

| Attribute | Value |
|-----------|-------|
| **Status** | ⏸️ Deferred |
| **Priority** | P0 - Critical |
| **Impact** | High - Redis overload |
| **Effort** | Medium |
| **File** | `app/jobs/room_update_broadcast_job.rb` |

**User Experience:**

A room's name or settings change. Every member's sidebar needs to update to reflect the new state.

- **Current:** The job already has a 5-second debounce lock to prevent thundering herd. Renders a membership-specific partial per user (unread state, involvement, badges vary per user), then publishes each to Redis individually.
- **Deferred:** Redis pipelining was attempted but reverted. The existing debounce provides adequate protection for current scale. Will revisit if Redis becomes a bottleneck.

**Problem:**

Renders a membership-specific partial per user (unread, involvement, and badge state vary per membership), then publishes each to Redis individually. There is already a 5-second debounce lock in the job.

```ruby
# Current implementation
def perform(room)
  room.memberships.visible.find_each do |membership|
    broadcast_membership_update(membership, room)
  end
end

def broadcast_membership_update(membership, room)
  SIDEBAR_SECTIONS.each do |list_name|
    html = render_partial_for(membership, list_name, room)  # Renders partial per user!
    Turbo::StreamsChannel.broadcast_replace_to(...)
  end
end
```

**Impact at Scale:**
- Popular room with 200 members: 400 renders + 400 Redis publishes
- Multiple room updates per minute = severe Redis and CPU pressure
- Estimated: 1000 operations per room update in busy rooms

**Recommended Fix:**

```ruby
def perform(room)
  return unless room.active? && room.sidebar_room?

  # Debounce rapid updates (already implemented via Kredis lock)
  lock_key = "room_update_broadcast_job_lock:#{room.id}"
  return unless Kredis.redis.set(lock_key, "1", nx: true, ex: 5)

  # Membership-specific partials must still render per user; focus on batching/pipelining
  room.memberships.visible.find_each do |membership|
    broadcast_membership_update(membership, room)
  end
end
```

**Acceptance Criteria:**
- [ ] Keep debounce/lock (already present)
- [ ] Reduce per-membership render cost where possible
- [ ] Batch/pipeline Redis operations where possible
- [ ] Add performance test comparing before/after

---

### CRIT-3: Global `unread_rooms` Channel Thundering Herd

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P0 - Critical |
| **Impact** | High - thundering herd |
| **Effort** | Medium |
| **File** | `app/models/room.rb:204-221` |

**User Experience:**

Anyone posts a message in any room. Users who are disconnected (not actively viewing that room) need their sidebar to show the room as unread.

- **Before:** Every message broadcast to a global `unread_rooms` channel. If 500 users are connected, all 500 receive every broadcast and must check "is this relevant to me?" Client-side waste + WebSocket congestion.
- **After:** Only the users who are actually disconnected from that room receive a broadcast on their personal `user_{id}_unreads` channel. Other users never see the message.

**Problem:**

Every message broadcasts to ALL connected users via a global channel, regardless of room membership. Note: a user-scoped unread channel already exists and is subscribed to by the client, but the global channel is still used.

```ruby
# Current implementation
ActionCable.server.broadcast("unread_rooms", {
  roomId: room.id,
  roomSize: room.messages_count,
  roomUpdatedAt: created_at.iso8601
})
```

**Impact at Scale:**
- 500 connected users = 500 WebSocket writes per message
- Users receive updates for rooms they don't belong to
- Wastes bandwidth and client CPU processing irrelevant updates

**Recommended Fix:**

```ruby
# Broadcast only to room members who aren't currently connected to the room
room.memberships.visible.disconnected.pluck(:user_id).each do |user_id|
  ActionCable.server.broadcast(
    "user_#{user_id}_unreads",
    { roomId: room.id, roomSize: room.messages_count, roomUpdatedAt: created_at.iso8601 }
  )
end
```

**Acceptance Criteria:**
- [x] Ensure user-scoped unread channel (`user_{id}_unreads`) is used for all unread updates
- [x] Update JavaScript subscription to use user-scoped channel
- [x] Only broadcast to room members
- [x] Skip users currently connected to the room
- [x] Update channel tests
- [x] Delete unused `UnreadRoomsChannel`
- [x] Add regression test: `assert_no_broadcasts "unread_rooms"` prevents reintroduction

---

### CRIT-4: `UnreadMentionsNotifierJob` N+1 Queries

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P0 - Critical |
| **Impact** | Medium - job duration |
| **Effort** | High |
| **File** | `app/jobs/unread_mentions_notifier_job.rb` |

**User Experience:**

This is a scheduled job (runs at 9am/6pm) that emails users about unread @mentions. No direct user interaction triggers it.

- **Before:** For each user, query their memberships, then for each membership query unread messages with dynamic `.since()` filters. 1000 users × 10 memberships = ~10,000 database queries. Job takes minutes.
- **After:** One SQL query finds all unread mentions across all users, grouped by user. Then iterate to send emails. Job completes in seconds.

**Problem:**

Despite using `includes`, the job triggers N+1 queries due to dynamic conditions in `unread_notifications` that cannot be preloaded.

```ruby
# Current implementation
User.active.subscribed("notifications").find_each do |user|
  unread_messages = user.memberships.visible.unread
    .includes(room: :users, unread_notifications: :creator)
    .flat_map { |m| m.unread_notifications.since(m.notified_until || m.room.created_at).since(7.days.ago) }
  # ...
end
```

**Impact at Scale:**
- 500 users × 20 memberships = 10,000+ membership loads
- Each membership loads room.users (potentially 100+ users per room)
- Job could take 10+ minutes during peak periods

**Recommended Fix:**

```ruby
def perform
  # Pre-compute all unread mentions in a single query
  unread_by_user = Message.active
    .joins(:room, :mentions)
    .joins("INNER JOIN memberships ON memberships.room_id = messages.room_id")
    .where("messages.created_at > memberships.unread_at")
    .where("messages.created_at > COALESCE(memberships.notified_until, rooms.created_at)")
    .where("messages.created_at > ?", 7.days.ago)
    .where("messages.created_at <= ?", 12.hours.ago)
    .where(memberships: { active: true })
    .where.not("memberships.involvement = 'invisible'")
    .includes(:creator)
    .group_by { |m| m.mentions.first&.user_id }

  User.active.subscribed("notifications")
      .where(id: unread_by_user.keys)
      .find_each do |user|
    messages = unread_by_user[user.id]
    next if messages.blank?

    NotifierMailer.unread_mentions(user, messages.sort_by(&:created_at)).deliver_now
    user.memberships.update_all(notified_until: Time.current)
  end
end
```

**Acceptance Criteria:**
- [x] Rewrite to use single consolidated query
- [x] Eliminate N+1 patterns
- [x] Add job duration logging
- [ ] Target: < 60 seconds for 500 users (needs production verification)

---

## 2. Database Query Issues

### DB-1: Missing Index on `memberships.unread_at`

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P1 - High |
| **Impact** | Medium - query performance |
| **Effort** | Low |
| **File** | `db/migrate/20260124044642_add_unread_at_index_to_memberships.rb` |

**User Experience:**

You open Campfire and your sidebar loads. The app needs to find which rooms have unread messages for you.

- **Before:** The database scanned through all your memberships to find ones with `unread_at` set. With 50+ room memberships, this added latency to every page load.
- **After:** A targeted index on `(user_id, unread_at)` lets the database jump directly to your unread rooms. Sidebar loads faster.

**Problem:**

Multiple queries filter by `unread_at` without index coverage:
- `scope :read, -> { where(unread_at: nil) }`
- `scope :unread, -> { where.not(unread_at: nil) }`
- `room.memberships.where(unread_at: created_at)`

**Current Indexes:**
```ruby
t.index ["room_id", "created_at"]
t.index ["room_id", "user_id", "involvement"]
t.index ["room_id", "user_id"], unique: true
t.index ["room_id"]
t.index ["user_id"]
# No index on unread_at!
```

**Recommended Fix:**

```ruby
class AddUnreadAtIndexToMemberships < ActiveRecord::Migration[7.2]
  def change
    add_index :memberships, [:user_id, :unread_at],
              where: "active = 1 AND unread_at IS NOT NULL",
              name: "index_memberships_on_user_unread_active"

    add_index :memberships, [:room_id, :unread_at],
              name: "index_memberships_on_room_unread"
  end
end
```

**Acceptance Criteria:**
- [x] Create migration
- [ ] Run EXPLAIN ANALYZE on affected queries before/after
- [ ] Verify index is used in production

---

### DB-2: `Inbox::ThreadsQuery` Multiple Subselects

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P1 - High |
| **Impact** | Medium - page load latency |
| **Effort** | Medium |
| **File** | `app/models/inbox/threads_query.rb` |

**User Experience:**

You click Inbox → Threads to see all thread conversations you're part of.

- **Before:** The page runs 4 separate database queries, combines results in Ruby, then runs the final query. Each step waits for the previous one. The Threads tab feels noticeably slower than other inbox tabs.
- **After:** A single SQL query with subqueries fetches everything at once. The database optimizer can plan the entire operation efficiently.

**Problem:**

Executes 4 separate queries with Ruby array union, loading all IDs into memory.

```ruby
# Before: 4 queries + Ruby array operations
def all_accessible_thread_ids
  thread_ids_from_memberships | thread_ids_from_parent_rooms  # Ruby array union
end

def thread_ids_from_memberships
  user.memberships.active.visible.joins(:room)
      .where(rooms: { type: "Rooms::Thread" })
      .pluck(:room_id)  # Query 1
end

def thread_ids_from_parent_rooms
  Room.where(type: "Rooms::Thread")
      .joins(:parent_message)
      .where(messages: { room_id: parent_room_ids_with_everything_involvement })
      .pluck(:id)  # Query 2 (depends on Query 3)
end
```

**Implemented Fix:**

Consolidated into single SQL query with EXISTS subqueries:

```ruby
def call
  Message.active
         .joins(:room)
         .where.not(rooms: { type: "Rooms::Thread" })
         .where("messages.id IN (#{accessible_thread_parent_ids_sql})")
         .with_thread_summary
         .with_creator
         .order(thread_activity_order)
end

def accessible_thread_parent_ids_sql
  <<~SQL.squish
    SELECT DISTINCT threads.parent_message_id
    FROM rooms threads
    WHERE threads.active = 1
      AND threads.type = 'Rooms::Thread'
      AND threads.messages_count > 0
      AND (
        EXISTS (
          SELECT 1 FROM memberships
          WHERE memberships.room_id = threads.id
            AND memberships.user_id = #{user.id}
            AND memberships.active = 1
            AND memberships.involvement != 'invisible'
        )
        OR EXISTS (
          SELECT 1 FROM messages
          INNER JOIN memberships ON memberships.room_id = messages.room_id
          WHERE messages.id = threads.parent_message_id
            AND memberships.user_id = #{user.id}
            AND memberships.active = 1
            AND memberships.involvement = 'everything'
        )
      )
  SQL
end
```

**Acceptance Criteria:**
- [x] Consolidate to single SQL query
- [x] Eliminate Ruby array operations
- [x] Verify correct results match existing behavior (all 41 inbox/thread tests pass)

---

### DB-3: `Message.for_display` Over-Eager Loading

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P1 - High |
| **Impact** | Medium - memory usage |
| **Effort** | Medium |
| **File** | `app/models/message.rb:43-50` |

**User Experience:**

You view a room with messages that have threads. The page needs to show thread previews (participant avatars, reply count).

- **Before:** Every thread loaded ALL its messages to compute participants. A room with 10 threaded messages × 100 replies each = 1000+ message records loaded into memory. Page felt slow and memory-heavy.
- **After:** Thread previews use a single efficient query per thread (`participant_creators`) that fetches only unique creators via GROUP BY. Memory usage drops from O(messages) to O(5 participants per thread).

**Problem:**

`with_threads` loads ALL messages in every thread associated with displayed messages.

```ruby
scope :with_threads, -> {
  includes(threads: {
    messages: { creator: [ :badge, { avatar_attachment: { blob: :variant_records } } ] },
    visible_memberships: { user: [ :badge, { avatar_attachment: { blob: :variant_records } } ] }
  })
}
```

**Impact at Scale:**
- Loading 25 messages with 5 threads of 100 messages each = 500+ records
- Memory: ~50KB per message = 50MB+ per page load
- Includes avatar blobs for every thread participant

**Implemented Fix:**

```ruby
# New lightweight scope for thread previews
scope :with_thread_summary, -> { includes(:threads) }

# Updated for_display to use lightweight thread loading
scope :for_display, -> {
  with_rich_text_body_and_embeds
    .includes(:mentions)
    .with_creator
    .includes(attachment_attachment: { blob: :variant_records })
    .includes(boosts: { booster: { avatar_attachment: { blob: :variant_records } } })
    .with_thread_summary  # Changed from with_threads
}

# In Rooms::Thread model - efficient participant fetching
def participant_creators(limit: 5)
  User.where(id: messages.active.group(:creator_id).order("MIN(created_at)").limit(limit).select(:creator_id))
      .includes(:badge, avatar_attachment: { blob: :variant_records })
end
```

**Acceptance Criteria:**
- [x] Create `with_thread_summary` scope
- [x] Replace `with_threads` in `for_display` with `with_thread_summary`
- [x] Add `participant_creators` method to `Rooms::Thread`
- [x] Update `_threads.html.erb` partial to use efficient method
- [x] Update inbox queries to use `with_thread_summary`

---

### DB-4: `with_has_unread_notifications` Complex Subquery

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P2 - Medium |
| **Impact** | Medium - query complexity |
| **Effort** | Medium |
| **File** | `app/models/membership.rb:19-50` |

**User Experience:**

Your sidebar shows a red dot on rooms where you have unread @mentions or DMs.

- **Before:** For each room in your sidebar, the database runs a complex nested query checking messages, mentions, and room types. With 20 rooms visible, that's 20 complex subqueries.
- **After:** The notification status could be cached on the membership record or computed more efficiently, reducing sidebar render time.

**Problem:**

Triple-nested EXISTS subquery executed per membership row.

```ruby
scope :with_has_unread_notifications, -> {
  select(
    "memberships.*",
    <<~SQL.squish
    EXISTS (
      SELECT 1 FROM messages
      WHERE messages.room_id = memberships.room_id
        AND messages.created_at >= COALESCE(memberships.unread_at, ...)
        AND (
          EXISTS (SELECT 1 FROM rooms WHERE rooms.id = memberships.room_id AND rooms.type = 'Rooms::Direct')
          OR EXISTS (SELECT 1 FROM mentions WHERE mentions.message_id = messages.id AND mentions.user_id = memberships.user_id)
          OR messages.mentions_everyone = true
        )
    ) AS preloaded_has_unread_notifications
    SQL
  )
}
```

**Recommended Fix:**

Mentions already has an index on `[:user_id, :message_id]`; focus on caching and verifying plan usage:

```ruby
# Consider caching on membership record
class Membership < ApplicationRecord
  def has_unread_notifications?
    return cached_has_unread_notifications if cached_has_unread_notifications_computed?
    compute_has_unread_notifications
  end
end
```

**Verification Results (2026-01-24):**

Benchmarked at **0.62ms** for 24 memberships. EXPLAIN QUERY PLAN confirms optimal index usage:
- `index_memberships_on_user_id` for membership lookup
- `index_messages_on_room_id_and_created_at` for message filtering
- `index_mentions_on_user_id_and_message_id` (covering index) for mention checks

No optimization needed - SQL complexity doesn't translate to performance issues.

**Acceptance Criteria:**
- [x] Confirm existing indexes are used (all 3 indexes hit correctly)
- [x] Evaluate caching strategy (not needed at 0.62ms)
- [x] Run EXPLAIN ANALYZE (shows optimal plan)

---

### DB-5: `Bookmark.with_bookmark_status` Extra Query

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P3 - Low |
| **Impact** | Low - extra query |
| **Effort** | Low |
| **File** | `app/models/bookmark.rb` |

**User Experience:**

You view a room and each message shows whether you've bookmarked it (star icon filled or empty).

- **Before:** After loading messages, a separate query fetches all your bookmarks for those messages. Two round trips to the database.
- **After:** Bookmark status is included in the original message query via LEFT JOIN. Single query, slightly faster page load.

**Problem:**

Always executes separate query even when messages relation could include this.

```ruby
def self.with_bookmark_status(messages, user: Current.user)
  message_ids = messages.is_a?(ActiveRecord::Relation) ? messages.pluck(:id) : messages.map(&:id)
  bookmarked_ids = active.where(user: user, message_id: message_ids).pluck(:message_id).to_set
  messages.each { |message| message.bookmarked = bookmarked_ids.include?(message.id) }
end
```

**Recommended Fix:**

```ruby
# Add to Message model
scope :with_bookmark_status_for, ->(user) {
  joins(<<~SQL)
    LEFT JOIN bookmarks
    ON bookmarks.message_id = messages.id
    AND bookmarks.user_id = #{user.id}
    AND bookmarks.active = 1
  SQL
  .select("messages.*, (bookmarks.id IS NOT NULL) as is_bookmarked")
}
```

**Acceptance Criteria:**
- [x] Add scope with LEFT JOIN (`with_bookmark_status_for`)
- [x] Update callers to use new scope
- [x] Remove separate query pattern (kept `Bookmark.with_bookmark_status` for backward compatibility)

---

## 3. WebSocket/Real-time Issues

### WS-1: `broadcast_notifications` Per-Membership Iteration

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P1 - High |
| **Impact** | Medium - Redis load |
| **Effort** | Low |
| **File** | `app/models/message/broadcasts.rb:15-27` |

**User Experience:**

Someone posts a message with `@everyone` in a busy room with 500 members.

- **Before:** 500 individual Redis PUBLISH commands fire sequentially. This hammers Redis and can cause a brief spike in latency for all real-time updates across the app.
- **After:** AnyCable batching collects all 500 publishes and sends them efficiently. Redis handles the batch, no latency spike.

**Problem:**

For `@everyone` mentions, broadcasts individually to each membership.

```ruby
def broadcast_notifications(ignore_if_older_message: false)
  memberships = if mentions_everyone?
    room.memberships
  else
    room.memberships.where(user_id: mentionee_ids)
  end

  memberships.each do |membership|
    ActionCable.server.broadcast "user_#{membership.user_id}_notifications", { roomId: room.id }
  end
end
```

**Implemented Fix:**

Uses AnyCable's built-in batching when available (any environment where AnyCable gem is loaded), falls back to ActionCable otherwise:

```ruby
def broadcast_notifications(ignore_if_older_message: false)
  user_ids = notification_recipient_ids(ignore_if_older_message)
  return if user_ids.empty?

  payload = { roomId: room.id }

  # Use AnyCable batching for efficient Redis pipelining when available
  if defined?(AnyCable) && AnyCable.broadcast_adapter.respond_to?(:batching)
    AnyCable.broadcast_adapter.batching do
      user_ids.each do |user_id|
        AnyCable.broadcast("user_#{user_id}_notifications", payload)
      end
    end
  else
    user_ids.each do |user_id|
      ActionCable.server.broadcast "user_#{user_id}_notifications", payload
    end
  end
end

def notification_recipient_ids(ignore_if_older_message)
  scope = mentions_everyone? ? room.memberships : room.memberships.where(user_id: mentionee_ids)
  scope = scope.where("unread_at IS NOT NULL AND unread_at <= ?", created_at) if ignore_if_older_message
  scope.pluck(:user_id)
end
```

**Acceptance Criteria:**
- [x] Use AnyCable batching for efficient batch publishes
- [x] Filter in SQL via `notification_recipient_ids` method
- [x] Graceful fallback when batching not available

---

### WS-2: `PresenceChannel` Database Query on Every Subscribe

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P2 - Medium |
| **Impact** | Low - connection overhead |
| **Effort** | Low |
| **File** | `app/channels/presence_channel.rb` |

**User Experience:**

You open Campfire and your browser establishes WebSocket connections to each visible room for real-time updates.

- **Before:** The `present` method called `membership` 3 times (guard clause, update, broadcast). With 10 rooms = 30 queries just to establish presence.
- **After:** Use a local variable in `present` to query once. 10 rooms = 10 queries. `absent` and `refresh` still do fresh lookups (correct for handling membership changes).

**Problem:**

The `present` method called `membership` multiple times:

```ruby
def present
  return unless membership      # Query 1

  membership.present            # Query 2
  broadcast_read_room           # → membership.room_id = Query 3
end
```

**Impact at Scale:**
- User viewing 10 rooms = 30 queries on subscribe (3 per room)

**Implemented Fix:**

Use a local variable within `present` (not instance-level memoization):

```ruby
def present
  m = membership                # Single query
  return unless m

  m.present
  ActionCable.server.broadcast "user_#{current_user.id}_reads", { room_id: m.room_id }
end
```

**Why not instance memoization?**

Caching `@membership` across the channel lifecycle would cause errors if the membership is deleted while the WebSocket is connected. `absent` and `refresh` need fresh lookups to handle this gracefully.

**Result:**
- Subscribe: 3 queries → 1 query per room
- `absent`/`refresh`: Still fresh lookups (safe for membership changes)

**Acceptance Criteria:**
- [x] Reduce queries in `present` method
- [x] Keep fresh lookups in `absent`/`refresh` for safety
- [x] All channel tests passing

---

## 4. SQLite-Specific Issues

### SQLITE-1: FTS5 Index Updates Block Message Creation

| Attribute | Value |
|-----------|-------|
| **Status** | ⏸️ Deferred (not worth the complexity) |
| **Priority** | P1 - High |
| **Impact** | Low (measured ~1.7% overhead) |
| **Effort** | Low |
| **File** | `app/models/message/searchable.rb` |

**Benchmark Results:**

| Operation | Time per message |
|-----------|------------------|
| Message create | 66.01ms |
| FTS5 indexing | 1.13ms |
| **Total (sync)** | 67.14ms |

FTS5 indexing adds only **1.7% overhead** (~1.13ms) to message creation. The bulk of the 66ms is from other callbacks (broadcasts, ActionText, etc).

**Decision:** Not worth the added complexity. Moving to a background job would:
- Add test complexity (every search test needs `perform_enqueued_jobs` wrapper)
- Introduce eventual consistency for search
- Save only ~1ms per message

The synchronous approach is simpler and the overhead is negligible.

**User Experience:**

You type a message and hit Send. The FTS5 index update adds ~1ms - imperceptible to users.

**Current Implementation (kept as-is):**

```ruby
after_create_commit :create_in_index

def create_in_index
  execute_sql_with_binds "insert into message_search_index(rowid, body) values (?, ?)", id, plain_text_body
end
```

---

### SQLITE-2: Write Contention from Counter Caches

| Attribute | Value |
|-----------|-------|
| **Status** | ⏸️ Deferred |
| **Priority** | P2 - Medium |
| **Impact** | Medium - write contention |
| **Effort** | Medium |
| **File** | `app/models/message.rb`, `app/models/room.rb` |

**User Experience:**

Multiple people post messages simultaneously in a busy room.

- **Before:** Each message triggers 3 database writes: the message itself, updating the room's `last_active_at`, and incrementing the message counter. SQLite serializes all writes, so concurrent posters queue up behind each other.
- **After:** Counter updates happen asynchronously in background jobs. Message creation is faster, reducing the window where SQLite is locked.

**Problem:**

Each message creates 3 writes: message INSERT, room.last_active_at UPDATE, counter cache UPDATE.

**Recommended Fix:**

```ruby
# Batch counter cache updates
class Message < ApplicationRecord
  belongs_to :room  # Remove counter_cache: true

  after_create_commit :increment_room_messages_count_later

  private

  def increment_room_messages_count_later
    IncrementCounterJob.perform_later("Room", room_id, :messages_count)
  end
end

class IncrementCounterJob < ApplicationJob
  def perform(model_class, id, column)
    model_class.constantize.where(id: id).update_all("#{column} = #{column} + 1")
  end
end
```

**Acceptance Criteria:**
- [ ] Async counter cache updates
- [ ] Verify counts remain accurate
- [ ] Monitor SQLite busy timeout waits

---

### SQLITE-3: Verify WAL Mode and Optimizations

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P2 - Medium |
| **Impact** | Medium - overall performance |
| **Effort** | Low |
| **File** | `config/initializers/sqlite_optimizations.rb` (missing in repo) |

**User Experience:**

General app responsiveness, especially under concurrent load.

- **Before:** Default SQLite settings may not be optimal for a web application. Readers might block writers, cache might be too small, etc.
- **After:** WAL mode enables concurrent reads during writes. Larger cache reduces disk I/O. Memory-based temp storage speeds up complex queries. Everything feels slightly faster.

**Verification Needed:**

Note: `config/database.yml` already sets `timeout: 5000`, `retries: 1000`, and `default_transaction_mode: immediate`, but there are no explicit WAL/cache_size pragmas.

```ruby
# Verify these are set in production
ActiveRecord::Base.connection.execute("PRAGMA journal_mode;")  # Should be "wal"
ActiveRecord::Base.connection.execute("PRAGMA synchronous;")   # Should be "NORMAL"
ActiveRecord::Base.connection.execute("PRAGMA cache_size;")    # Should be negative (KB)
```

**Recommended Settings:**

```ruby
# config/initializers/sqlite_optimizations.rb (to be created)
if ActiveRecord::Base.connection.adapter_name == "SQLite"
  ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL;")
  ActiveRecord::Base.connection.execute("PRAGMA synchronous=NORMAL;")
  ActiveRecord::Base.connection.execute("PRAGMA cache_size=-64000;")  # 64MB
  ActiveRecord::Base.connection.execute("PRAGMA temp_store=MEMORY;")
end
```

**Verification Results (2026-01-24):**

Rails 8 automatically configures optimal SQLite settings. Verified in both development and production:

| Setting | Value | Notes |
|---------|-------|-------|
| journal_mode | wal | ✅ Optimal for concurrent access |
| synchronous | 1 (NORMAL) | ✅ Good balance of safety/speed |
| mmap_size | 128MB | ✅ Memory-mapped I/O enabled |
| cache_size | 2000 pages (~8MB) | ✅ Acceptable |
| wal_autocheckpoint | 1000 | ✅ Default |

No manual initializer needed - Rails 8's sqlite3 adapter handles this automatically.

**Acceptance Criteria:**
- [x] Verify WAL mode in production
- [x] Set appropriate cache size (Rails 8 default)
- [x] Document SQLite tuning

---

## 5. Caching Opportunities

### CACHE-1: `active_member_count` Computed on Every Room Show

| Attribute | Value |
|-----------|-------|
| **Status** | 🟢 Complete |
| **Priority** | P3 - Low |
| **Impact** | Low - repeated queries |
| **Effort** | Low |
| **File** | `app/models/room.rb:133` |

**User Experience:**

You view a room and the header shows "42 members".

- **Before:** Every page load counts active members by joining memberships and users tables. Same query runs repeatedly even though member counts rarely change.
- **After:** Member count is cached for 5 minutes. First view queries the database, subsequent views use the cached value. Slight reduction in database load.

**Problem:**

```ruby
def active_member_count
  memberships.visible.joins(:user).merge(User.active).count
end
```

**Implemented Fix:**

```ruby
# In Room model
def active_member_count
  Rails.cache.fetch("room:#{id}:active_member_count", expires_in: 5.minutes) do
    memberships.visible.joins(:user).merge(User.active).count
  end
end

def invalidate_member_count_cache
  Rails.cache.delete("room:#{id}:active_member_count")
end

# In Membership model
after_commit :invalidate_room_member_count_cache

def invalidate_room_member_count_cache
  room&.invalidate_member_count_cache

  # Also invalidate previous room if room_id changed
  if saved_change_to_room_id? && room_id_before_last_save
    Room.find_by(id: room_id_before_last_save)&.invalidate_member_count_cache
  end
end
```

**Acceptance Criteria:**
- [x] Add caching with 5-minute TTL
- [x] Add cache invalidation on membership changes
- [x] All tests passing

---

### CACHE-2: Fragment Cache Sidebar

| Attribute | Value |
|-----------|-------|
| **Status** | 🔴 Not started |
| **Priority** | P3 - Low |
| **Impact** | Low - page load |
| **Effort** | Medium |
| **File** | `app/views/users/sidebars/` |

**User Experience:**

Every page load renders the sidebar with all your rooms.

- **Before:** Each room in the sidebar is rendered fresh on every request. With 30 rooms, that's 30 partial renders.
- **After:** The entire sidebar (or large sections) could be fragment-cached and invalidated only when your memberships change. Faster page loads for repeated navigation.

**Problem:**

Sidebar already uses fragment caching per membership and direct rooms are rendered with caching; consider adding a higher-level fragment if needed.

**Recommended Fix:**

```erb
<%# Consider adding a higher-level fragment cache if needed %>
<% cache [Current.user, "sidebar", Current.user.memberships.maximum(:updated_at)] do %>
  <%= render "users/sidebars/rooms/direct_rooms", memberships: @direct_memberships %>
  <%= render "users/sidebars/rooms/shared_rooms", memberships: @shared_memberships %>
<% end %>
```

**Acceptance Criteria:**
- [ ] Decide whether higher-level fragment caching is needed
- [ ] If added, use a cache key with membership timestamp
- [ ] Test cache invalidation scenarios

---

### CACHE-3: User Avatar URL Caching

| Attribute | Value |
|-----------|-------|
| **Status** | 🔴 Not started |
| **Priority** | P3 - Low |
| **Impact** | Low - reduces joins |
| **Effort** | Low |
| **File** | `app/models/user.rb` |

**User Experience:**

Every message, thread preview, and user list shows avatar images.

- **Before:** Generating each avatar URL requires joining through Active Storage tables (attachments → blobs → variant_records). With 50 messages on screen, that's a lot of joins.
- **After:** Avatar URLs are cached per user. Once computed, they're reused until the user changes their avatar. Fewer database joins, slightly faster renders.

**Problem:**

Multiple places load `user.avatar_attachment` with `blob.variant_records`.

**Recommended Fix:**

```ruby
def avatar_url_cached
  Rails.cache.fetch("user:#{id}:avatar_url:v#{updated_at.to_i}", expires_in: 1.hour) do
    avatar.attached? ? Rails.application.routes.url_helpers.url_for(avatar) : nil
  end
end
```

**Acceptance Criteria:**
- [ ] Cache avatar URLs
- [ ] Invalidate on avatar change
- [ ] Update partials to use cached method

---

## 6. Background Job Issues

### JOB-1: Web Push Delivery May Overwhelm Thread Pool

| Attribute | Value |
|-----------|-------|
| **Status** | 🔴 Not started |
| **Priority** | P2 - Medium |
| **Impact** | Medium - push delivery delays |
| **Effort** | Low |
| **File** | `lib/web_push/pool.rb` |

**User Experience:**

Someone posts an `@everyone` message in a large room. Everyone with push notifications enabled should get a notification.

- **Before:** All push notifications are queued to the thread pool at once. With 1000 subscribers, the pool queue explodes. Some notifications may be delayed or dropped if memory pressure builds.
- **After:** Backpressure mechanism throttles queueing when the pool is busy. Notifications are delivered steadily rather than in a flood. More reliable delivery, less memory pressure.

**Problem:**

`find_each` with default batch size (1000) could overwhelm thread pool queue.

```ruby
def queue(payload, subscriptions)
  subscriptions.find_each do |subscription|
    deliver_later(payload, subscription)
  end
end
```

**Recommended Fix:**

```ruby
def queue(payload, subscriptions)
  subscriptions.find_each(batch_size: 100) do |subscription|
    # Backpressure: wait if queue is getting full
    sleep(0.1) while delivery_pool.queue_length > 8000
    deliver_later(payload, subscription)
  end
end
```

**Acceptance Criteria:**
- [ ] Add backpressure mechanism
- [ ] Reduce batch size
- [ ] Monitor queue depth

---

### JOB-2: Solid Queue Polling Interval

| Attribute | Value |
|-----------|-------|
| **Status** | ⏸️ Deferred |
| **Priority** | P3 - Low |
| **Impact** | Low - reduces polling overhead |
| **Effort** | Low |
| **File** | `config/queue.yml` |

**User Experience:**

Background jobs (emails, broadcasts, indexing) are processed by Solid Queue workers.

**Analysis (2026-01-24):**

Current config already uses 1s polling for workers, which is 10x slower than Solid Queue's default of 0.1s. Going to 2s would halve polling queries but add up to 1s latency to job pickup. For a real-time chat app with broadcasts and notifications, the marginal reduction in database queries isn't worth the added latency.

| Setting | Solid Queue Default | Current |
|---------|---------------------|---------|
| Worker polling | 0.1s | 1s |
| Dispatcher polling | 1s | 1s |

**Decision:** Keep at 1s. Already conservative; further reduction not worth the latency trade-off.

---

## Benchmarking & Monitoring

### Recommended Instrumentation

Add to `config/initializers/performance_monitoring.rb`:

```ruby
# Log slow queries
ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  if event.duration > 100  # Log queries over 100ms
    Rails.logger.warn "[SLOW QUERY] #{event.duration.round(1)}ms: #{event.payload[:sql]}"
  end
end

# Track broadcast timing
module BroadcastInstrumentation
  def broadcast_create
    start = Time.current
    super
    duration = (Time.current - start) * 1000
    Rails.logger.info "[BROADCAST] Message##{id} completed in #{duration.round(1)}ms"
  end
end
Message::Broadcasts.prepend(BroadcastInstrumentation)
```

### Load Testing Recommendations

Run with:
- 100 concurrent WebSocket connections
- 50 messages per minute across 10 rooms
- Monitor:
  - SQLite `PRAGMA busy_timeout` waits
  - Redis memory and pub/sub throughput
  - Job queue depth and latency
  - Memory usage per request

---

## Summary by Priority

### P0 - Critical (This Week)

| ID | Issue | Effort | Status |
|----|-------|--------|--------|
| CRIT-1 | O(n) broadcasts + heavy preload in `broadcast_to_inbox_threads` | Low | 🟢 Complete |
| CRIT-2 | `RoomUpdateBroadcastJob` per-membership | Medium | ⏸️ Deferred |
| CRIT-3 | Global `unread_rooms` thundering herd | Medium | 🟢 Complete |
| CRIT-4 | `UnreadMentionsNotifierJob` N+1 | High | 🟢 Complete |

### P1 - High (This Sprint)

| ID | Issue | Effort | Status |
|----|-------|--------|--------|
| DB-1 | Missing index on `memberships.unread_at` | Low | 🟢 Complete |
| DB-2 | `Inbox::ThreadsQuery` multiple subselects | Medium | 🟢 Complete |
| DB-3 | `Message.for_display` over-eager loading | Medium | 🟢 Complete |
| WS-1 | `broadcast_notifications` per-membership | Low | 🟢 Complete |
| SQLITE-1 | FTS5 blocks message creation | Low | ⏸️ Deferred |

### P2 - Medium (Next Sprint)

| ID | Issue | Effort | Status |
|----|-------|--------|--------|
| DB-4 | `with_has_unread_notifications` subquery | Medium | 🟢 Complete |
| WS-2 | `PresenceChannel` query per subscribe | Low | 🟢 Complete |
| SQLITE-2 | Counter cache write contention | Medium | ⏸️ Deferred |
| SQLITE-3 | Verify WAL mode (initializer missing) | Low | 🟢 Complete |
| JOB-1 | Web push thread pool backpressure | Low | 🔴 Not started |

### P3 - Low (Backlog)

| ID | Issue | Effort | Status |
|----|-------|--------|--------|
| DB-5 | `Bookmark.with_bookmark_status` extra query | Low | 🟢 Complete |
| CACHE-1 | Cache `active_member_count` | Low | 🟢 Complete |
| CACHE-2 | Sidebar caching (evaluate higher-level fragment) | Medium | 🔴 Not started |
| CACHE-3 | Cache avatar URLs | Low | 🔴 Not started |
| JOB-2 | Solid Queue polling interval | Low | ⏸️ Deferred |

---

## Changelog

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-23 | Performance Oracle | Initial audit |
| 2026-01-24 | Claude | Implemented CRIT-1: Move `broadcast_to_inbox_threads` to `BroadcastInboxThreadsJob` |
| 2026-01-24 | Claude | Implemented CRIT-3: Replace global `unread_rooms` channel with user-scoped broadcasts |
| 2026-01-24 | Claude | Implemented CRIT-4: Rewrite `UnreadMentionsNotifierJob` with consolidated query |
| 2026-01-24 | Claude | Deferred CRIT-2: Redis pipelining reverted, existing debounce is adequate |
| 2026-01-24 | Claude | Implemented DB-1: Add indexes on `memberships.unread_at` |
| 2026-01-24 | Claude | Implemented DB-3: Replace `with_threads` with `with_thread_summary` and add `participant_creators` |
| 2026-01-24 | Claude | Implemented WS-2: Use local variable in `present` to reduce 3 queries to 1 |
| 2026-01-24 | Claude | Implemented CACHE-1: Cache `active_member_count` with 5-minute TTL |
| 2026-01-24 | Claude | Implemented DB-2: Consolidate ThreadsQuery into single SQL with EXISTS subqueries |
| 2026-01-24 | Claude | Deferred SQLITE-1: Benchmarked at 1.7% overhead (~1ms), not worth added complexity |
| 2026-01-24 | Claude | Implemented WS-1: Use AnyCable batching for broadcast_notifications |
| 2026-01-24 | Claude | Deferred SQLITE-2: Benchmarked at ~50ms/message, ~21 msg/sec throughput; async counter adds complexity for marginal gain |
| 2026-01-24 | Claude | Complete SQLITE-3: Verified Rails 8 auto-configures WAL mode and optimizations in dev and production |
| 2026-01-24 | Claude | Implemented DB-5: Add `with_bookmark_status_for` LEFT JOIN scope to eliminate extra bookmark query |
| 2026-01-24 | Claude | Verified DB-4: Benchmarked at 0.62ms with optimal index usage, no optimization needed |
| 2026-01-24 | Claude | Verified CRIT-1: Message creation ~37-49ms (constant regardless of thread size), job enqueue 0.39ms |
| 2026-01-24 | Claude | Verified CRIT-3: User-scoped broadcasts working, added regression test for global channel |
| 2026-01-24 | Claude | Fixed CRIT-1 race condition: Check `thread.messages_count` at execution time to prevent duplicate inbox entries |
| 2026-01-24 | Claude | Deferred JOB-2: Worker polling already at 1s (10x slower than default 0.1s), further reduction not worth latency trade-off |
