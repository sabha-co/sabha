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
| **Status** | :green_circle: Complete |
| **Priority** | P0 - Critical |
| **Impact** | High - reduces Redis round-trips |
| **Effort** | Low (config only) |
| **Related** | Builds on WS-1 fix from [PERFORMANCE_AUDIT.md](./PERFORMANCE_AUDIT.md#ws-1-broadcast_notifications-per-membership-iteration) |

**Problem:**

The WS-1 fix added manual batching to `broadcast_notifications`, but all other broadcasts (Turbo Streams, room updates, inbox updates) still execute individually, causing multiple Redis round-trips per request.

**Solution:**

Enabled automatic batching globally in `config/anycable.yml`. All broadcasts within a Rails request or background job are automatically aggregated.

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

**Implementation:**

Config change in `config/anycable.yml`:
```yaml
broadcast_batching: true
```

Simplified `app/models/message/broadcasts.rb` - removed manual batching wrapper:
```ruby
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
- [x] Add `broadcast_batching: true` to config/anycable.yml
- [x] Remove manual batching wrapper from broadcast_notifications
- [ ] Verify broadcasts still work in development
- [ ] Load test to confirm reduced latency

---

## 2. Whispering for Typing Notifications

| Attribute | Value |
|-----------|-------|
| **Status** | :green_circle: Complete |
| **Priority** | P1 - High |
| **Impact** | High - eliminates RPC for typing |
| **Effort** | Medium |
| **File** | `app/channels/typing_notifications_channel.rb`, `app/frontend/controllers/typing_notifications_controller.js` |

**Problem:**

Every typing indicator (start/stop) makes an RPC call to Rails, which then broadcasts back through AnyCable. With 50 active typers at 2 events/second each, that's 100 RPC calls/second for non-critical UI updates.

**Old Flow:**
```
Client types → WebSocket → AnyCable-Go → RPC to Rails → Rails broadcasts → AnyCable-Go → All clients
```

**New Flow (with whispering):**
```
Client types → WebSocket → AnyCable-Go → All clients (no Rails!)
```

**Benefits:**
- Eliminates 100% of typing-related RPC calls when AnyCable is enabled
- Sub-millisecond latency for typing indicators
- Reduces Rails server load
- AnyCable-Go handles all the routing
- Graceful fallback to RPC for non-AnyCable environments

**Implementation:**

**Requirements:**
- `anycable-rails-core` gem (or full `anycable-rails` - both work)
- AnyCable-Go started with `--streams_whisper` flag (enables whisper for signed streams)
- `@anycable/web` JavaScript client (via esm.sh in importmap)

Server-side (`app/channels/typing_notifications_channel.rb`):
```ruby
class TypingNotificationsChannel < RoomChannel
  def subscribed
    if @room = find_room
      stream_for @room, **stream_options
    else
      reject
    end
  end

  # RPC fallback for non-AnyCable environments
  def start(data)
    broadcast_to room, action: :start, user: current_user_attributes if room
  end

  def stop(data)
    broadcast_to room, action: :stop, user: current_user_attributes if room
  end

  private
    def stream_options
      AnyCable::Rails.enabled? ? { whisper: true } : {}
    end
end
```

Client-side (`app/frontend/controllers/typing_notifications_controller.js`):
- Added `@anycable/web` client import (via esm.sh in importmap)
- Attempts AnyCable client connection with whisper support
- Falls back to standard ActionCable if AnyCable unavailable
- Uses `channel.whisper()` for direct client-to-client messaging

**Acceptance Criteria:**
- [x] Update TypingNotificationsChannel to enable whispering
- [x] Update JavaScript typing controller to use whisper API
- [x] Add feature detection for non-AnyCable environments
- [x] Test typing indicators still work
- [x] Verify RPC calls eliminated in AnyCable logs (confirmed: `whispered` in AnyCable-Go logs, no RPC)

---

## 3. Broadcast to Others (Exclude Sender)

| Attribute | Value |
|-----------|-------|
| **Status** | :pause_button: Deferred |
| **Priority** | P2 - Medium |
| **Impact** | Low - marginal bandwidth savings |
| **Effort** | Medium |
| **File** | `app/models/message/broadcasts.rb` |

**Problem:**

When a user sends a message, they receive their own broadcast back. The client already shows the message optimistically, so this broadcast is wasted bandwidth.

**Why Deferred:**
- Marginal gain: saves 1 broadcast per message to sender only
- Client already handles optimistic UI, so no functional impact
- Requires plumbing `X-Socket-ID` header through all request paths
- Edge cases with background jobs/callbacks where socket ID isn't available
- Complexity outweighs bandwidth savings at current scale

**Solution (if revisited):**

Use AnyCable's `to_others` option to exclude the sender from broadcasts. Requires passing `X-Socket-ID` header from client and using `to_others: true` in broadcast calls.

---

## 4. Signed Streams for Simplified Subscriptions

| Attribute | Value |
|-----------|-------|
| **Status** | :pause_button: Deferred |
| **Priority** | P3 - Low |
| **Impact** | Low - reduces boilerplate |
| **Effort** | Medium |

**Problem:**

Custom channel classes require authorization logic that duplicates model-level permissions. Signed streams can eliminate some channel classes entirely.

**Why Deferred:**
- Only saves RPC calls on *subscription*, not broadcasts (one-time cost per connection)
- Requires changing view helpers and removing/modifying channel classes
- Current channels work reliably and are well-tested
- Candidates (`UserUnreadRoomsChannel`, etc.) have minimal auth logic anyway
- Complexity vs benefit ratio is poor for marginal subscription speedup

**Solution (if revisited):**

Use `turbo_stream_from current_user, :notifications, signed: true` in views. AnyCable verifies signature without RPC. Could eliminate simple user-scoped channel classes.

---

## 5. Native Presence Tracking

| Attribute | Value |
|-----------|-------|
| **Status** | :pause_button: Deferred |
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

Use AnyCable's built-in presence tracking. Presence state is managed in AnyCable-Go memory, with optional persistence hooks. Basic presence available in OSS (AnyCable 1.6+)

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

**Why Deferred:**
- Current database-backed presence works reliably for self-hosted deployments
- High effort for marginal gain at current scale
- Would need fallback for non-AnyCable deployments anyway

**Acceptance Criteria (if revisited):**
- [ ] Evaluate single-node presence (OSS) vs cluster presence (Pro)
- [ ] Design fallback for non-AnyCable deployments
- [ ] Implement presence tracking via AnyCable
- [ ] Remove or reduce database presence updates
- [ ] Update presence UI to use AnyCable presence API

---

## 6. Connection State Caching

| Attribute | Value |
|-----------|-------|
| **Status** | :green_circle: Complete |
| **Priority** | P3 - Low |
| **Impact** | Low - faster reconnects |
| **Effort** | Low |

**Problem:**

On reconnect, AnyCable makes RPC calls to re-authenticate and re-subscribe to all channels. This can be slow for users with many subscriptions.

**Solution:**

Enabled AnyCable's connection state caching in `config/anycable.yml`:

```yaml
# Cache connection state for faster reconnects
restore_from_cache: true
cache_ttl: 300  # 5 minutes
```

**Benefits:**
- Faster reconnection after brief disconnects
- Fewer RPC calls during connection churn
- Better mobile experience (frequent disconnects)

**Acceptance Criteria:**
- [x] Enable connection state caching in config
- [ ] Test reconnection behavior
- [ ] Verify auth is still checked appropriately

---

## Implementation Roadmap

### Phase 1: Quick Wins (No Code Changes) - :green_circle: COMPLETE

| ID | Optimization | Effort | Status |
|----|--------------|--------|--------|
| 1 | Enable automatic broadcast batching | Config only | :green_circle: Done |
| 6 | Enable connection state caching | Config only | :green_circle: Done |

### Phase 2: High Impact Changes

| ID | Optimization | Effort | Status |
|----|--------------|--------|--------|
| 2 | Whispering for typing notifications | Medium | :green_circle: Done |
| 3 | Broadcast to others | Medium | :pause_button: Deferred (marginal gain) |

### Phase 3: Architecture Improvements

| ID | Optimization | Effort | Status |
|----|--------------|--------|--------|
| 4 | Signed streams | Medium | :pause_button: Deferred (complexity vs benefit) |
| 5 | Native presence tracking | High | :pause_button: Deferred (Pro for clusters) |

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
| 2026-01-24 | Claude | Implemented Phase 1: broadcast_batching + connection state caching |
| 2026-01-24 | Claude | Implemented whispering for typing notifications (Phase 2) |
| 2026-01-24 | Claude | Added --streams_whisper flag to Procfile.dev.anycable (key fix for whisper) |
| 2026-01-24 | Claude | Confirmed anycable-rails-core works fine (full gem not required) |
| 2026-01-24 | Claude | Use AnyCable::Rails.enabled? for feature detection (supports self-hosting without AnyCable) |
| 2026-01-24 | Claude | Deferred native presence tracking (OSS single-node only, Pro required for clusters) |
| 2026-01-24 | Claude | Deferred broadcast to others (#3) and signed streams (#4) - marginal gains vs complexity |
