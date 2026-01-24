# AnyCable Optimizations for Scale

**Date:** 2026-01-24
**Target Scale:** Thousands of messages/day, hundreds of concurrent WebSocket connections
**Status:** Planning

---

## Overview

This document outlines AnyCable-specific optimizations to improve Campfire-CE's real-time performance. These build on the existing AnyCable HTTP RPC setup documented in [ANYCABLE_IMPLEMENTATION.md](./ANYCABLE_IMPLEMENTATION.md).

**Current AnyCable Setup:**
- HTTP RPC mode (no gRPC dependency)
- HTTP broadcast adapter
- Manual broadcast batching in `broadcast_notifications` (WS-1 fix)

**Already Implemented:**
- :green_circle: **WS-1**: AnyCable batching for `broadcast_notifications` - see [PERFORMANCE_AUDIT.md](./PERFORMANCE_AUDIT.md#ws-1-broadcast_notifications-per-membership-iteration)

**Benchmark Baseline (from load tests):**

| Metric | Action Cable | AnyCable | Improvement |
|--------|-------------|----------|-------------|
| WebSocket connect time | 7.33s | 43.82ms | 167x faster |
| Messages/second | 358/s | 714/s | 2x throughput |

---

## Optimization Tracking

### Legend

| Status | Meaning |
|--------|---------|
| :red_circle: | Not started |
| :yellow_circle: | In progress |
| :green_circle: | Complete |
| :pause_button: | Deferred |

---

## 1. Automatic Broadcast Batching

| Attribute | Value |
|-----------|-------|
| **Status** | :red_circle: Not started |
| **Priority** | P0 - Critical |
| **Impact** | High - reduces Redis round-trips |
| **Effort** | Low (config only) |
| **Related** | Builds on WS-1 fix from [PERFORMANCE_AUDIT.md](./PERFORMANCE_AUDIT.md#ws-1-broadcast_notifications-per-membership-iteration) |

**Problem:**

The WS-1 fix added manual batching to `broadcast_notifications`, but all other broadcasts (Turbo Streams, room updates, inbox updates) still execute individually, causing multiple Redis round-trips per request.

**Current State (WS-1 fix):**

```ruby
# Manual batching in app/models/message/broadcasts.rb (WS-1 implementation)
# This batches notification broadcasts, but other broadcasts are still individual
if defined?(AnyCable) && AnyCable.broadcast_adapter.respond_to?(:batching)
  AnyCable.broadcast_adapter.batching do
    user_ids.each do |user_id|
      AnyCable.broadcast("user_#{user_id}_notifications", payload)
    end
  end
end
```

**Solution:**

Enable automatic batching globally. All broadcasts within a Rails request or background job are automatically aggregated.

```yaml
# config/anycable.yml
default: &default
  http_rpc_mount_path: "/_anycable"
  broadcast_adapter: http
  broadcast_batching: true  # Add this line
```

**How It Works:**

AnyCable hooks into Rails executor to batch broadcasts:
1. HTTP request starts → batch opens
2. Multiple `broadcast` calls collected in memory
3. Request ends → single batched publish to AnyCable-Go
4. Same behavior for background jobs

**Benefits:**
- Reduces Redis/HTTP round-trips from O(n) to O(1) per request
- Maintains broadcast ordering within batch
- Zero code changes required
- Works with all broadcast methods (ActionCable, Turbo Streams, AnyCable direct)

**After enabling, remove manual batching:**

```ruby
# app/models/message/broadcasts.rb - simplified
def broadcast_notifications(ignore_if_older_message: false)
  user_ids = notification_recipient_ids(ignore_if_older_message)
  return if user_ids.empty?

  payload = { roomId: room.id }

  # Auto-batching handles aggregation - no manual wrapping needed
  user_ids.each do |user_id|
    ActionCable.server.broadcast "user_#{user_id}_notifications", payload
  end
end
```

**Acceptance Criteria:**
- [ ] Add `broadcast_batching: true` to config/anycable.yml
- [ ] Remove manual batching wrapper from broadcast_notifications
- [ ] Verify broadcasts still work in development
- [ ] Load test to confirm reduced latency

---

## 2. Whispering for Typing Notifications

| Attribute | Value |
|-----------|-------|
| **Status** | :red_circle: Not started |
| **Priority** | P1 - High |
| **Impact** | High - eliminates RPC for typing |
| **Effort** | Medium |
| **File** | `app/channels/typing_notifications_channel.rb` |

**Problem:**

Every typing indicator (start/stop) makes an RPC call to Rails, which then broadcasts back through AnyCable. With 50 active typers at 2 events/second each, that's 100 RPC calls/second for non-critical UI updates.

**Current Flow:**

```
Client types → WebSocket → AnyCable-Go → RPC to Rails → Rails broadcasts → AnyCable-Go → All clients
```

**Current Implementation:**

```ruby
class TypingNotificationsChannel < RoomChannel
  def start(data)
    broadcast_to room, action: :start, user: current_user_attributes if room
  end

  def stop(data)
    broadcast_to room, action: :stop, user: current_user_attributes if room
  end
end
```

**Solution:**

Use AnyCable whispering - client-initiated broadcasts that bypass Rails entirely.

**New Flow:**

```
Client types → WebSocket → AnyCable-Go → All clients (no Rails!)
```

**Implementation:**

```ruby
# app/channels/typing_notifications_channel.rb
class TypingNotificationsChannel < RoomChannel
  def subscribed
    super
    # Enable whispering - clients can broadcast directly
    stream_for room, whisper: true if room
  end

  # Remove start/stop methods - clients whisper directly
  # Keep them as fallback for non-AnyCable environments
  def start(data)
    return if anycable_whisper_enabled?
    broadcast_to room, action: :start, user: current_user_attributes if room
  end

  def stop(data)
    return if anycable_whisper_enabled?
    broadcast_to room, action: :stop, user: current_user_attributes if room
  end

  private

  def anycable_whisper_enabled?
    defined?(AnyCable) && AnyCable.config.whisper_enabled?
  end
end
```

**Client-side changes:**

```javascript
// app/frontend/controllers/typing_controller.js
startTyping() {
  if (this.channel.whisper) {
    // Direct whisper - no server round-trip
    this.channel.whisper({ action: "start", user: this.currentUser })
  } else {
    // Fallback to RPC
    this.channel.perform("start")
  }
}

stopTyping() {
  if (this.channel.whisper) {
    this.channel.whisper({ action: "stop", user: this.currentUser })
  } else {
    this.channel.perform("stop")
  }
}
```

**Benefits:**
- Eliminates 100% of typing-related RPC calls
- Sub-millisecond latency for typing indicators
- Reduces Rails server load
- AnyCable-Go handles all the routing

**Limitations:**
- Only one whisper stream per channel subscription
- No server-side validation of whisper content
- Requires AnyCable (falls back to RPC otherwise)

**Acceptance Criteria:**
- [ ] Update TypingNotificationsChannel to enable whispering
- [ ] Update JavaScript typing controller to use whisper API
- [ ] Add feature detection for non-AnyCable environments
- [ ] Test typing indicators still work
- [ ] Verify RPC calls eliminated in AnyCable logs

---

## 3. Broadcast to Others (Exclude Sender)

| Attribute | Value |
|-----------|-------|
| **Status** | :red_circle: Not started |
| **Priority** | P2 - Medium |
| **Impact** | Medium - reduces echo traffic |
| **Effort** | Medium |
| **File** | `app/models/message/broadcasts.rb` |

**Problem:**

When a user sends a message, they receive their own broadcast back. The client already shows the message optimistically, so this broadcast is wasted bandwidth and can cause UI flicker.

**Current Flow:**

```
User sends message → Server broadcasts to ALL subscribers → User receives their own message back
```

**Solution:**

Use AnyCable's `to_others` option to exclude the sender from broadcasts.

**Implementation:**

Step 1: Pass socket ID from client

```javascript
// app/frontend/controllers/messages_controller.js
async submitMessage(event) {
  const socketId = this.cable?.sessionId

  const response = await fetch(this.formTarget.action, {
    method: 'POST',
    headers: {
      'X-Socket-ID': socketId,  // AnyCable uses this to exclude sender
      'Accept': 'text/vnd.turbo-stream.html'
    },
    body: new FormData(this.formTarget)
  })
}
```

Step 2: Use `to_others` in broadcasts

```ruby
# app/models/message/broadcasts.rb
def broadcast_create
  broadcast_append_to room, :messages,
    target: [room, :messages],
    partial: "messages/message",
    locals: { current_room: room },
    to_others: true  # Exclude the sender
end
```

Step 3: For indirect broadcasts (callbacks, jobs), wrap in context

```ruby
# When broadcasting from a callback where socket ID isn't available
AnyCable::Rails.broadcasting_to_others do
  Turbo::StreamsChannel.broadcast_append_to(room, :messages, ...)
end
```

**Benefits:**
- Eliminates redundant broadcasts to message sender
- Prevents potential UI flicker from duplicate messages
- Reduces WebSocket traffic by ~1/N per message (N = room members)

**Acceptance Criteria:**
- [ ] Update JavaScript to send X-Socket-ID header
- [ ] Add `to_others: true` to message broadcasts
- [ ] Verify sender doesn't receive their own messages
- [ ] Ensure optimistic UI still works correctly

---

## 4. Signed Streams for Simplified Subscriptions

| Attribute | Value |
|-----------|-------|
| **Status** | :red_circle: Not started |
| **Priority** | P3 - Low |
| **Impact** | Low - reduces boilerplate |
| **Effort** | Medium |

**Problem:**

Custom channel classes require authorization logic that duplicates model-level permissions. Signed streams can eliminate some channel classes entirely.

**Current Pattern:**

```ruby
# Custom channel with auth logic
class UserNotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user, :notifications
  end
end
```

```erb
<%# View must use turbo_stream_from with channel %>
<%= turbo_stream_from current_user, :notifications %>
```

**With Signed Streams:**

```erb
<%# View uses signed stream - no channel class needed %>
<%= turbo_stream_from current_user, :notifications, signed: true %>
```

AnyCable verifies the signature and allows subscription without RPC.

**Candidates for Signed Streams:**
- `UserUnreadRoomsChannel` - user-scoped, no complex auth
- `UnreadNotificationsChannel` - user-scoped, no complex auth
- `InboxMentionsChannel` - user-scoped, simple auth

**Not Candidates (need RPC for auth):**
- `RoomChannel` - requires membership verification
- `PresenceChannel` - requires membership + state updates
- `TypingNotificationsChannel` - uses whispering

**Benefits:**
- Eliminates RPC calls for subscription
- Reduces channel class boilerplate
- Faster initial connection (fewer RPC round-trips)

**Acceptance Criteria:**
- [ ] Identify channels that can use signed streams
- [ ] Update views to use `signed: true`
- [ ] Remove or simplify corresponding channel classes
- [ ] Verify subscriptions work without RPC

---

## 5. Native Presence Tracking

| Attribute | Value |
|-----------|-------|
| **Status** | :red_circle: Not started |
| **Priority** | P3 - Low |
| **Impact** | Medium - offloads presence to AnyCable |
| **Effort** | High |
| **File** | `app/channels/presence_channel.rb`, `app/models/concerns/connectable.rb` |

**Problem:**

Presence tracking currently updates the database (`memberships.connected_at`) on every connect/disconnect. This creates write pressure and requires cleanup jobs.

**Current Implementation:**

```ruby
# app/models/concerns/connectable.rb
def present
  update!(connected_at: Time.current)
end

def absent
  update!(connected_at: nil)
end
```

**Solution:**

Use AnyCable's built-in presence tracking. Presence state is managed in AnyCable-Go memory, with optional persistence hooks.

```ruby
# app/channels/presence_channel.rb
class PresenceChannel < ApplicationCable::Channel
  def subscribed
    room = Room.find_by(id: params[:id])
    reject and return unless room && membership

    # AnyCable tracks presence automatically
    stream_for room, presence: true
  end

  # Called by AnyCable when presence changes
  def presence_joined(info)
    # Optional: broadcast join event
  end

  def presence_left(info)
    # Optional: broadcast leave event
  end
end
```

**Benefits:**
- Eliminates database writes for presence updates
- Presence state survives brief disconnects (configurable)
- Built-in presence list API
- Reduces `connected_at` column updates

**Considerations:**
- Requires AnyCable Pro for full presence features
- Need to handle presence differently for non-AnyCable deployments
- May need to keep database presence for offline queries

**Acceptance Criteria:**
- [ ] Evaluate AnyCable Pro presence features
- [ ] Design fallback for non-AnyCable deployments
- [ ] Implement presence tracking via AnyCable
- [ ] Remove or reduce database presence updates
- [ ] Update presence UI to use AnyCable presence API

---

## 6. Connection State Caching

| Attribute | Value |
|-----------|-------|
| **Status** | :red_circle: Not started |
| **Priority** | P3 - Low |
| **Impact** | Low - faster reconnects |
| **Effort** | Low |

**Problem:**

On reconnect, AnyCable makes RPC calls to re-authenticate and re-subscribe to all channels. This can be slow for users with many subscriptions.

**Solution:**

Enable AnyCable's connection state caching to reduce RPC calls on reconnect.

```yaml
# config/anycable.yml
default: &default
  # ... existing config

  # Cache connection state for faster reconnects
  restore_from_cache: true
  cache_ttl: 300  # 5 minutes
```

**Benefits:**
- Faster reconnection after brief disconnects
- Fewer RPC calls during connection churn
- Better mobile experience (frequent disconnects)

**Acceptance Criteria:**
- [ ] Enable connection state caching in config
- [ ] Test reconnection behavior
- [ ] Verify auth is still checked appropriately

---

## Implementation Roadmap

### Phase 1: Quick Wins (No Code Changes)

| ID | Optimization | Effort |
|----|--------------|--------|
| 1 | Enable automatic broadcast batching | Config only |
| 6 | Enable connection state caching | Config only |

### Phase 2: High Impact Changes

| ID | Optimization | Effort |
|----|--------------|--------|
| 2 | Whispering for typing notifications | Medium |
| 3 | Broadcast to others | Medium |

### Phase 3: Architecture Improvements

| ID | Optimization | Effort |
|----|--------------|--------|
| 4 | Signed streams | Medium |
| 5 | Native presence tracking | High |

---

## Testing AnyCable Optimizations

### Development Testing

```bash
# Start with AnyCable enabled
ANYCABLE_ENABLED=true bin/dev

# Watch AnyCable-Go logs for RPC calls
# After whispering: typing should NOT trigger RPC
# After batching: fewer broadcast log entries per request
```

### Load Testing

```bash
# Run load test with optimizations
bin/load-anycable -h server.example.com --ssh-user root -u 500 --anycable

# Compare metrics:
# - RPC calls/second (should decrease)
# - Broadcast latency (should decrease)
# - Messages/second throughput (should increase)
```

### Metrics to Track

| Metric | Before | Target |
|--------|--------|--------|
| RPC calls for typing | 100/s (50 typers) | 0/s |
| Broadcasts per message | O(n) individual | O(1) batched |
| Reconnect time | ~500ms | ~100ms |

---

## References

- [AnyCable Rails Extensions](https://docs.anycable.io/rails/extensions)
- [AnyCable Broadcast Batching](https://docs.anycable.io/rails/extensions#broadcast-batching)
- [AnyCable Whispering](https://docs.anycable.io/rails/extensions#whispering)
- [AnyCable Signed Streams](https://docs.anycable.io/anycable-go/signed_streams)
- [AnyCable Pro Presence](https://docs.anycable.io/anycable-go/presence)
- [Evil Martians: Real-time Stress Testing](https://evilmartians.com/chronicles/real-time-stress-anycable-k6-websockets-and-yabeda)

---

## Changelog

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-24 | Claude | Initial document |
| 2026-01-24 | Claude | Added reference to WS-1 fix (AnyCable batching already implemented) |
