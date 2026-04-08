# Plan: WebSocket Support for Bot API

## Goal

Add a `BotEventsChannel` so bots can receive events via WebSocket instead of webhooks. Eliminates the requirement for the bot's host to be network-reachable from Sabha.

## Research Findings & Assumption Corrections

### Confirmed

- **`User.authenticate_bot(bot_key)`** exists at `app/models/user/bot.rb:21` — splits `bot_key` on `-`, finds active bot by ID + token.
- **`request.params` works in AnyCable HTTP RPC** — confirmed by existing SaaS `wid` query param pattern in `saas/config/initializers/tenanting/tenant_resolver.rb:24`. AnyCable-Go forwards query params to the Rails RPC endpoint.
- **anycable-rails-core 1.6.1** supports this approach. No JWT needed — query param auth via `request.params` in `Connection#connect` is the established pattern (same as `wid`).
- **Webhook payloads** are well-structured JSON built by `Webhook#create_payload` (`app/models/webhook.rb:83`). Reusable for WebSocket events.
- **Bot membership filtering** exists at `Room#bot_memberships_for_webhook` (`app/models/room.rb:261`). Similar logic needed for WebSocket delivery.
- **Cross-tenant isolation** works automatically — in SaaS mode, `User.authenticate_bot` queries `active_bots` scoped to the current tenant's database. A bot_key from workspace A cannot authenticate in workspace B.

### Corrected from Design Doc

1. **Webhooks are triggered from controllers, not model callbacks.** `deliver_webhooks_to_bots` lives in the `NotifyBots` concern and is called from `MessagesController`, `Messages::BoostsController`, `UsersController`, and `Accounts::UsersController`. The design doc proposed `after_create_commit :broadcast_to_bot_channels` on the Message model — this is wrong. WebSocket broadcast should follow the same controller-initiated pattern via `NotifyBots`.

2. **Webhook payloads require `base_url` from the request.** `Webhook::UrlBuilder` needs `base_url` (from `request.base_url + request.script_name`) to build absolute URLs in payloads. WebSocket broadcasts happen from controllers where `request` is available, so this works — but it means we can't move delivery to a model callback without passing `base_url` explicitly.

3. **Bot involvement filtering matters.** `bot_memberships_for_webhook` applies rules: only bots with `involvement: [:mentions, :everything]` and a webhook configured. For `message_created` in non-direct rooms, only bots that are mentioned or `@everyone` receive the event. WebSocket delivery should reuse this same filtering logic rather than broadcasting to all bot rooms unconditionally.

4. **Reply capability needs design thought.** Webhook delivery supports synchronous replies — the bot responds to the HTTP POST and Sabha creates a message from the response body. WebSocket doesn't have this request/response pattern. Bots using WebSocket must reply via the REST API (which they already do for non-reply webhook flows). This is fine — Mattermost works the same way.

### SaaS Mode Considerations

- **Tenant resolution for WebSocket:** Bots connect with `?bot_key=xxx&wid=workspace_id`. The existing tenant resolver (`request.env["sabha.workspace_id"] || request.params["wid"]`) already handles this — no changes needed to the tenant resolver.
- **Channel tenant context:** The `activerecord-tenanted` gem wraps all channel commands with `around_command :with_tenant` automatically. `BotEventsChannel#subscribed` will run within the correct tenant context.
- **Registration response must include `wid`:** In SaaS mode, the registration response needs to include the workspace ID so the plugin knows what `wid` value to pass. Currently `ApplicationRecord.current_tenant` is available in the controller.
- **Broadcasting from controllers:** In SaaS mode, controller code runs within the correct tenant context (set by PathRewriter + TenantSelector). `ActionCable.server.broadcast` from a controller will work correctly.

## Implementation Plan

### Step 1: Bot authentication in `ApplicationCable::Connection`

**File:** `app/channels/application_cable/connection.rb`

Add a `connect_bot` path that checks `request.params["bot_key"]` before falling through to session cookie auth. Must run after `super` in SaaS mode (so `current_tenant` is set).

```ruby
def connect
  super if Sabha.saas?

  if request.params["bot_key"].present?
    connect_bot
  elsif Sabha.saas?
    connect_saas
  else
    connect_single_tenant
  end
end

def connect_bot
  bot = if Sabha.saas?
    return reject_unauthorized_connection unless current_tenant
    ApplicationRecord.with_tenant(current_tenant) { User.authenticate_bot(request.params["bot_key"]) }
  else
    User.authenticate_bot(request.params["bot_key"])
  end

  reject_unauthorized_connection unless bot
  self.current_user = bot
end
```

**Why `with_tenant` explicitly?** The gem's `around_command` wraps channel commands but the `connect` method runs outside that wrapper. In SaaS mode, `current_tenant` is set by the gem but the DB query needs an explicit tenant context.

### Step 2: `BotEventsChannel`

**File:** `app/channels/bot_events_channel.rb`

Simple channel that bots subscribe to. Streams from a bot-specific stream name.

```ruby
class BotEventsChannel < ApplicationCable::Channel
  def subscribed
    unless current_user.bot?
      reject
      return
    end

    stream_from bot_stream_name
  end

  private
    def bot_stream_name
      "bot_events:#{current_user.id}"
    end
end
```

**Design choice: single stream per bot, not per-room.** The webhook system already handles room-level filtering in `bot_memberships_for_webhook`. Broadcasting to a single bot stream keeps subscription management simple — no need to subscribe/unsubscribe as bots join/leave rooms. The filtering happens at broadcast time, same as webhooks.

### Step 3: Broadcast to bot WebSocket alongside webhook delivery

**File:** `app/controllers/concerns/notify_bots.rb`

Extend `deliver_webhooks_to_bots` (or add a parallel method) to also broadcast JSON to connected bots' WebSocket streams. Bots with a webhook get webhook delivery. All eligible bots with active WebSocket connections get the broadcast. A bot can receive both — the plugin is responsible for deduplication.

Simpler approach: rename to `notify_bots` and handle both channels:

```ruby
def notify_bots(item, event)
  base_url = request.base_url + request.script_name
  room = item.try(:room) || item.try(:message)&.room

  if room
    bots_to_notify = room.bot_memberships_for_events(item, event)
    bots_to_notify.each do |membership|
      bot = membership.user
      payload = Webhook.build_event_payload(item, event, bot_key: bot.bot_key, base_url: base_url)

      # WebSocket delivery (immediate, non-blocking)
      ActionCable.server.broadcast("bot_events:#{bot.id}", JSON.parse(payload))

      # Webhook delivery (async job, only if webhook configured)
      if bot.webhook_url.present?
        reply = membership.receives_mentions? && event == :created
        bot.deliver_webhook_later(item, event, reply: reply, base_url: base_url)
      end
    end
  else
    # Account-level events (user_created, user_deleted) — broadcast to all bots
    User.active_bots.each do |bot|
      payload = Webhook.build_event_payload(item, event, bot_key: bot.bot_key, base_url: base_url)
      ActionCable.server.broadcast("bot_events:#{bot.id}", JSON.parse(payload))
      bot.deliver_webhook_later(item, event, base_url: base_url) if bot.webhook_url.present?
    end
  end
end
```

**Concern:** This doubles the work for bots that have both webhook and WebSocket. The plugin should handle deduplication (drop webhook events when WebSocket is connected). Alternatively, we could skip webhook delivery when the bot has an active WebSocket connection — but detecting "active connection" server-side is unreliable (the bot may have disconnected without cleanup). Safer to let the plugin deduplicate.

**Alternative (simpler):** Don't change `deliver_webhooks_to_bots` at all. Add a separate `broadcast_to_bot_channels` method. Call both from controllers. This avoids touching the existing webhook logic.

### Step 4: Extract payload building from `Webhook`

**File:** `app/models/webhook.rb`

Currently `create_payload` is a private instance method on `Webhook`. Extract the payload building into a class method or module so it can be reused for WebSocket broadcasts without a `Webhook` record.

```ruby
# In Webhook or a new Webhook::Payload module
def self.build_event_payload(item, event, bot_key:, base_url:)
  urls = UrlBuilder.new(base_url, bot_key)
  # ... same payload building logic ...
end
```

### Step 5: `bot_memberships_for_events` on Room

**File:** `app/models/room.rb`

Rename or generalize `bot_memberships_for_webhook` to `bot_memberships_for_events`. Currently it filters by `joins(:webhook)` — bots without a webhook URL are excluded. For WebSocket, bots without a webhook should also be eligible.

```ruby
def bot_memberships_for_events(item, event)
  eligible = memberships.active
    .where(involvement: [:mentions, :everything])
    .where(user_id: User.active_bots.pluck(:id))
    .includes(:user)

  # Same mention/direct filtering logic as today
  if direct?
    eligible.to_a
  elsif item.is_a?(Message) && event == :created
    eligible.to_a.select { |m| item.mentionees.include?(m.user) || item.mentions_everyone? }
  else
    eligible.to_a
  end
end
```

Keep `bot_memberships_for_webhook` as-is (with `joins(:webhook)` filter) or migrate callers to the new method.

### Step 6: Return `websocket_url` in registration response

**File:** `app/controllers/bots/registrations_controller.rb`

Add `websocket_url` to the registration response so the plugin knows where to connect.

```ruby
def registration_response
  @bot.reload

  {
    bot_key: @bot.bot_key,
    name: @bot.name,
    webhook_url: @bot.webhook_url,
    websocket_url: websocket_url_for_bot,
    rooms: @bot.rooms.without_threads.map { |room|
      room.as_bot_json(bot_key: @bot.bot_key, url_helper: method(:room_bot_messages_url))
    }
  }
end

def websocket_url_for_bot
  base = ActionCable.server.config.url || "#{request.base_url}/cable"
  params = { bot_key: @bot.bot_key }
  params[:wid] = ApplicationRecord.current_tenant if Sabha.saas?
  "#{base}?#{params.to_query}"
end
```

### Step 7: Tests

1. **Connection test** — bot authenticates via `bot_key` query param (self-hosted and SaaS)
2. **Connection test** — invalid `bot_key` rejected
3. **Connection test** — SaaS cross-tenant rejection (bot from workspace A can't connect with workspace B's `wid`)
4. **Channel test** — bot subscribes to `BotEventsChannel`, receives broadcast
5. **Channel test** — non-bot user rejected from `BotEventsChannel`
6. **Integration test** — message created, bot receives event via WebSocket stream
7. **SaaS integration test** — same as above but with tenant context

## Files Changed

| File | Change |
|------|--------|
| `app/channels/application_cable/connection.rb` | Add `connect_bot` method |
| `app/channels/bot_events_channel.rb` | **New** — bot event streaming channel |
| `app/controllers/concerns/notify_bots.rb` | Add WebSocket broadcast alongside webhook delivery |
| `app/models/webhook.rb` | Extract `build_event_payload` class method |
| `app/models/room.rb` | Add `bot_memberships_for_events` (generalized from `bot_memberships_for_webhook`) |
| `app/controllers/bots/registrations_controller.rb` | Add `websocket_url` to response |
| `test/channels/application_cable/connection_test.rb` | Bot auth tests |
| `test/channels/bot_events_channel_test.rb` | **New** — channel subscription tests |
| `test/controllers/concerns/notify_bots_test.rb` | WebSocket broadcast tests |
| `saas/test/channels/application_cable/connection_test.rb` | SaaS bot auth tests |

## What This Does NOT Change

- **Existing webhook delivery** — untouched. Bots with webhooks continue to receive HTTP POSTs.
- **Bot REST API** — untouched. Bots still send messages, manage rooms, etc. via REST with `bot_key` in URL.
- **Browser WebSocket channels** — untouched. `RoomChannel`, `PresenceChannel`, etc. remain session-cookie auth only.
- **Turbo Stream broadcasts** — untouched. HTML broadcasts to browser clients are separate from JSON bot broadcasts.

## Open Questions

1. **Deduplication:** If a bot has both webhook and WebSocket, it receives events twice. Should Sabha skip webhook delivery when a WebSocket connection is active? Or let the plugin handle it? (Recommendation: let the plugin handle it — server-side connection detection is unreliable.)

2. **Room join/leave events:** When a bot joins or leaves a room, should we send a `room_joined`/`room_left` event over WebSocket? The webhook system doesn't have these today.

3. **Typing notifications:** Should bots receive typing events via WebSocket? Not in the webhook system today. Could be useful for AI assistants that want to show "thinking" state.

4. **Connection limits:** Should we limit the number of concurrent WebSocket connections per bot? AnyCable handles connection management, but a misbehaving bot could open many connections.
