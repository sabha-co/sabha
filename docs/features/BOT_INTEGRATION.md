# Bot Integration Guide

Sabha's bot API lets external programs post messages, read conversations, and respond to mentions. This guide covers building simple task bots and connecting AI agents like OpenClaw.

> **Breaking change (Bot API v2):** All HTTP endpoints now live under `/api/bots/` and authenticate with the `Authorization: Bearer <bot_key>` header. Outbound webhooks are HMAC-SHA256 signed. Self-hosted operators upgrading from earlier versions must update their bots to the new shape before restarting Sabha.

## Quick Start

### 1. Generate a bot invite URL

An admin visits `/account/bots` and clicks **Generate** under "Invite URL". This produces a single-use URL of the form `https://chat.example.com/join/JOIN_CODE`. Generating a new URL invalidates any previously generated one — only the most recent URL is active.

### 2. Register a bot

```bash
curl -X POST https://chat.example.com/join/JOIN_CODE \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{"name": "My Bot", "webhook_url": "https://my-server.com/webhook"}'
```

Response:

```json
{
  "bot_key": "42-AbCdEfGhIjKl",
  "webhook_secret": "whsec_...",
  "name": "My Bot",
  "webhook_url": "https://my-server.com/webhook",
  "base_url": "https://chat.example.com",
  "api_base_url": "https://chat.example.com/api/bots",
  "websocket_url": "wss://chat.example.com/cable?bot_key=42-AbCdEfGhIjKl",
  "rooms": [
    { "id": 1, "name": "General", "type": "Open",
      "messages_url": "https://chat.example.com/api/bots/rooms/1/messages" }
  ]
}
```

Store the `bot_key` and `webhook_secret` — both are shown only once. The `bot_key` authenticates API calls; the `webhook_secret` verifies inbound webhooks.

The invite URL is consumed on success. The bot is automatically added to all open rooms marked as auto-join, just like a human user.

### 3. Alternatively: create a bot via admin UI

Admins can create bots directly at `/account/bots` without issuing an invite URL. The admin sets the name, webhook URL, and manages the bot key from the UI.

---

## Authentication

All HTTP endpoints authenticate with `Authorization: Bearer <bot_key>`. The `bot_key` is a secret equivalent to a password — always use HTTPS.

```
Authorization: Bearer 42-AbCdEfGhIjKl
```

The WebSocket endpoint keeps `bot_key` in the query string (`wss://.../cable?bot_key=…`) because most WebSocket clients cannot set arbitrary headers during the handshake.

## API Reference

All endpoints are rooted at the `api_base_url` returned from registration (e.g. `https://chat.example.com/api/bots`).

| Action | Method | Endpoint |
|---|---|---|
| Post a message | POST | `/rooms/{room_id}/messages` |
| Send attachment | POST | `/rooms/{room_id}/messages` (multipart) |
| Edit own message | PATCH | `/rooms/{room_id}/messages/{id}` |
| Delete own message | DELETE | `/rooms/{room_id}/messages/{id}` |
| Read single message | GET | `/rooms/{room_id}/messages/{id}` |
| Reply in a thread | POST | `/rooms/{room_id}/messages/{message_id}/thread` |
| Read messages | GET | `/rooms/{room_id}/messages` |
| Add reaction | POST | `/rooms/{room_id}/messages/{message_id}/boosts` |
| Remove reaction | DELETE | `/rooms/{room_id}/messages/{message_id}/boosts/{boost_id}` |
| List room members | GET | `/rooms/{room_id}/members` |
| Add member to room | POST | `/rooms/{room_id}/members` |
| Remove member from room | DELETE | `/rooms/{room_id}/members/{user_id}` |
| Bot joins room | POST | `/rooms/{room_id}/membership` |
| Bot leaves room | DELETE | `/rooms/{room_id}/membership` |
| Search messages | GET | `/search?q=query` |
| List rooms | GET | `/rooms` |
| List joinable rooms | GET | `/rooms?joinable=true` |
| Create room | POST | `/rooms` |
| Update room | PATCH | `/rooms/{room_id}` |
| Archive room | DELETE | `/rooms/{room_id}` |
| Create a DM | POST | `/direct_messages` |
| Update bot settings | PATCH | `/profile` |
| API discovery | GET | `/skill` (top-level, unauthenticated) |

The `/skill` endpoint returns a plain-text document describing the full API with examples. It is designed to be readable by both humans and LLMs.

---

## Room Permissions

A bot's access to each room is controlled by its membership involvement:

- **Mentions** — webhook fires when @mentioned or in a DM. Response is auto-posted as a reply.
- **Muted** — no webhooks. Bot can still post and read via the API.

Admins configure permissions per room from the bot's detail page. Each room has its own permission page at `/account/bots/:id/rooms/:room_id/permission`.

By default, new bots join open rooms with "mentions" involvement.

### Thread and DM delivery

Inside a thread or direct message, a bot member receives **every** message — no mention required — matching how notifications work for human members of the same conversation. The "mentions" gate only applies to open and closed rooms.

---

## Simple Task Bots

For small automations — deploy notifications, CI alerts, standup reminders — you only need to POST messages. No webhook server required.

### Deploy notifier (bash)

```bash
BOT_KEY="42-AbCdEfGhIjKl"
ROOM_ID=1
API="https://chat.example.com/api/bots"

curl -X POST "$API/rooms/$ROOM_ID/messages" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: text/plain" \
  -d "Deploy complete: $(git log --oneline -1)"
```

### Scheduled reminder (cron)

```bash
# Every weekday at 9am
0 9 * * 1-5 curl -X POST "$API/rooms/$ROOM_ID/messages" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: text/plain" \
  -d "Standup time! What are you working on today?"
```

### GitHub webhook forwarder (Ruby)

A small Sinatra app that receives GitHub webhooks and posts to Sabha:

```ruby
require "sinatra"
require "net/http"
require "json"

BOT_KEY = ENV["SABHA_BOT_KEY"]
ROOM_ID = ENV["SABHA_ROOM_ID"]
API     = ENV["SABHA_API_BASE_URL"]  # e.g. https://chat.example.com/api/bots

post "/github" do
  payload = JSON.parse(request.body.read)
  action = payload["action"]
  repo = payload.dig("repository", "full_name")

  message = case request.env["HTTP_X_GITHUB_EVENT"]
  when "push"
    commits = payload["commits"]&.size || 0
    "#{payload["pusher"]["name"]} pushed #{commits} commit(s) to #{repo}"
  when "pull_request"
    "PR ##{payload["number"]} #{action}: #{payload.dig("pull_request", "title")}"
  when "issues"
    "Issue ##{payload["number"]} #{action}: #{payload.dig("issue", "title")}"
  end

  if message
    uri = URI("#{API}/rooms/#{ROOM_ID}/messages")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.post(uri.path, message,
        "Authorization" => "Bearer #{BOT_KEY}",
        "Content-Type"  => "text/plain")
    end
  end

  status 200
end
```

### Mentioning users

Use `@{user_id}` syntax in message bodies:

```bash
curl -X POST "$API/rooms/$ROOM_ID/messages" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: text/plain" \
  -d "Hey @{42}, your build failed."
```

### Editing a message

Bots can edit their own messages. The request body replaces the message content.

```bash
curl -X PATCH "$API/rooms/$ROOM_ID/messages/$MESSAGE_ID" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: text/plain" \
  -d "Updated: deploy complete (v2.1.0)"
```

### Deleting a message

Bots can delete their own messages (soft-delete).

```bash
curl -X DELETE "$API/rooms/$ROOM_ID/messages/$MESSAGE_ID" \
  -H "Authorization: Bearer $BOT_KEY"
```

Returns `204 No Content` on success.

### Adding a reaction

Send the emoji as plain text in the request body.

```bash
curl -X POST "$API/rooms/$ROOM_ID/messages/$MESSAGE_ID/boosts" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: text/plain" \
  -d "🎉"
```

Returns the boost ID which you can use to remove it later.

### Removing a reaction

```bash
curl -X DELETE "$API/rooms/$ROOM_ID/messages/$MESSAGE_ID/boosts/$BOOST_ID" \
  -H "Authorization: Bearer $BOT_KEY"
```

### Listing room members

```bash
curl "$API/rooms/$ROOM_ID/members" -H "Authorization: Bearer $BOT_KEY"
```

Returns an array of members with `id`, `name`, and `role`.

### Searching messages

```bash
curl "$API/search?q=deploy" -H "Authorization: Bearer $BOT_KEY"
```

Returns up to 50 matching messages with room context.

### Reading a single message

```bash
curl "$API/rooms/$ROOM_ID/messages/$MESSAGE_ID" -H "Authorization: Bearer $BOT_KEY"
```

### Discovering joinable rooms

List open rooms the bot can join (rooms it's not already in).

```bash
curl "$API/rooms?joinable=true" -H "Authorization: Bearer $BOT_KEY"
```

### Joining a room

```bash
curl -X POST "$API/rooms/$ROOM_ID/membership" -H "Authorization: Bearer $BOT_KEY"
```

### Leaving a room

```bash
curl -X DELETE "$API/rooms/$ROOM_ID/membership" -H "Authorization: Bearer $BOT_KEY"
```

### Creating a room

```bash
curl -X POST "$API/rooms" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "Bot Room", "type": "open"}'
```

### Updating a room

```bash
curl -X PATCH "$API/rooms/$ROOM_ID" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "New Name"}'
```

### Archiving a room

```bash
curl -X DELETE "$API/rooms/$ROOM_ID" -H "Authorization: Bearer $BOT_KEY"
```

### Adding a member to a room

```bash
curl -X POST "$API/rooms/$ROOM_ID/members" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id": 42}'
```

### Removing a member from a room

```bash
curl -X DELETE "$API/rooms/$ROOM_ID/members/$USER_ID" -H "Authorization: Bearer $BOT_KEY"
```

---

## Interactive Bots (Webhook-Driven)

Register a `webhook_url` when creating a bot. Sabha calls it when someone @mentions the bot or DMs it.

### How it works

1. User sends: "Hey @MyBot, what's the weather?"
2. Sabha POSTs to the bot's `webhook_url` with the signed payload
3. The bot verifies the signature and processes the message
4. The bot's HTTP response body is automatically posted as a reply

No second API call needed. Just return text.

### Webhook signature verification

Every outbound webhook is signed with HMAC-SHA256. Headers on every delivery:

```
X-Sabha-Signature: sha256=<hex>
X-Sabha-Timestamp: <unix-epoch-seconds>
X-Sabha-Event: message_created         # or message_updated, boost_created, etc.
X-Sabha-Delivery: <uuid>               # unique per delivery, for dedup / log correlation
```

To verify:

1. Read the raw request body and the `X-Sabha-Timestamp` header
2. Reject if `|now - timestamp| > 300` seconds (5-minute replay window)
3. Compute `expected = "sha256=" + HMAC_SHA256(webhook_secret, "{timestamp}.{raw_body}")`
4. Compare `expected` against `X-Sabha-Signature` with a timing-safe comparison
5. On any mismatch, respond `401 Unauthorized`

Reference implementation (Ruby):

```ruby
require "openssl"

def verify_sabha_webhook(request, webhook_secret)
  signature = request.env["HTTP_X_SABHA_SIGNATURE"]
  timestamp = request.env["HTTP_X_SABHA_TIMESTAMP"].to_i
  return false if signature.blank? || (Time.now.to_i - timestamp).abs > 300

  raw_body = request.body.read
  request.body.rewind
  expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, "#{timestamp}.#{raw_body}")

  ActiveSupport::SecurityUtils.secure_compare(expected, signature)
end
```

WebSocket events are NOT signed — the WebSocket connection is already authenticated with `bot_key` at handshake.

### Webhook payload

All URLs in the payload are absolute — you can call them directly.

```json
{
  "event": "message_created",
  "user": { "id": 1, "name": "Alice", "role": "member", "url": "https://chat.example.com/users/1" },
  "room": {
    "id": 5, "name": "General", "type": "Open",
    "members": 12, "has_bot": true,
    "messages_url": "https://chat.example.com/api/bots/rooms/5/messages"
  },
  "message": {
    "id": 10,
    "body": { "html": "<p>Hey @MyBot, what's the weather?</p>", "plain": "Hey @MyBot, what's the weather?" },
    "has_attachment": false,
    "attachment": null,
    "mentionees": [{ "id": 42, "name": "MyBot" }],
    "url": "https://chat.example.com/rooms/5@10",
    "created_at": "2026-04-07T12:00:00Z",
    "updated_at": "2026-04-07T12:00:00Z",
    "thread": null
  }
}
```

Messages with attachments include a signed download URL:

```json
"attachment": {
  "url": "https://chat.example.com/rails/active_storage/blobs/...",
  "filename": "photo.jpg",
  "content_type": "image/jpeg",
  "byte_size": 245760
}
```

Attachment URLs are signed and expire after 1 hour.

### Response conventions

| Response | Result |
|---|---|
| `200` with `Content-Type: text/plain` | Auto-posted as a message |
| `200` with `Content-Type: text/html` | Auto-posted as a rich message |
| `200` with binary content type | Auto-posted as a file attachment |
| Timeout (300s) or error | Error message posted to the room |

### Thread replies

To reply to a specific message in a thread instead of the main room:

```
POST /api/bots/rooms/{room_id}/messages/{message_id}/thread
Authorization: Bearer {bot_key}
Content-Type: text/plain

This is a threaded reply!
```

This creates a thread on the message (or finds an existing one) and posts the reply there.

### Minimal echo bot (Ruby)

```ruby
require "sinatra"
require "json"

post "/webhook" do
  # verify_sabha_webhook(request, ENV["WEBHOOK_SECRET"]) or halt 401
  payload = JSON.parse(request.body.read)
  plain_text = payload.dig("message", "body", "plain")
  sender = payload.dig("user", "name")

  content_type "text/plain"
  "#{sender} said: #{plain_text}"
end
```

---

## Real-Time Bots (WebSocket)

Bots can receive events over WebSocket instead of webhooks. This eliminates the requirement for the bot's host to be network-reachable from Sabha — the bot connects *outbound* to Sabha.

### How it works

1. Bot registers via `POST /join/{code}` and receives a `websocket_url` in the response
2. Bot opens a WebSocket connection to that URL (ActionCable protocol)
3. Bot subscribes to `BotEventsChannel`
4. Events arrive as JSON — same payload format as webhooks (but unsigned)

### Connecting

Use any ActionCable-compatible WebSocket client. The `websocket_url` from registration includes the `bot_key` as a query parameter.

```
wss://chat.example.com/cable?bot_key=42-AbCdEfGhIjKl
```

Subscribe to the bot events channel:

```json
{ "command": "subscribe", "identifier": "{\"channel\":\"BotEventsChannel\"}" }
```

### Event format

Events arrive as JSON messages with the same structure as webhook payloads. All event types are supported: `message_created`, `message_updated`, `message_deleted`, `boost_created`, `boost_deleted`, `user_created`, `user_deleted`.

### Sending replies

WebSocket is receive-only. To reply, use the REST API:

```bash
curl -X POST "$API/rooms/$ROOM_ID/messages" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: text/plain" \
  -d "Got your message!"
```

### Webhooks as fallback

Bots can use both connection modes simultaneously. If a `webhook_url` is configured, Sabha delivers events via both WebSocket and webhook. The bot client is responsible for deduplication (use `X-Sabha-Delivery` on the webhook side).

### Reconnection

Bots should implement reconnection with exponential backoff. Sabha's AnyCable server supports connection state caching — brief disconnects (under 5 minutes) restore cleanly.

---

## OpenClaw Integration

[OpenClaw](https://openclaw.ai) is an AI agent platform that connects to chat services. The [`openclaw-sabha`](https://github.com/openclaw/openclaw-sabha) plugin (v0.10.0+) implements the bearer-token auth and HMAC webhook verification documented here.

### Architecture

Sabha supports two connection modes. WebSocket is preferred — it matches the Mattermost plugin experience where the bot connects outbound, requiring no tunnel or reverse proxy.

**WebSocket mode (recommended):**

```
User @mentions bot in Sabha
        |
        v
Sabha pushes event via WebSocket ──> OpenClaw gateway receives event
                                              |
                                              v
                                       LLM processes message
                                              |
                                              v
                                       REST API POST (Bearer auth)
                                              |
                                              v
                                    Sabha receives reply
```

**Webhook mode (fallback):**

```
User @mentions bot in Sabha
        |
        v
Sabha calls webhook_url (HMAC-signed) ──> OpenClaw gateway verifies + receives
                                                    |
                                                    v
                                             LLM processes message
                                                    |
                                                    v
                                             HTTP 200 response body
                                                    |
                                                    v
                                          Sabha auto-posts reply
```

### How Sabha maps to OpenClaw concepts

| OpenClaw concept | Sabha equivalent |
|---|---|
| Channel | Sabha bot API |
| Bot token | `bot_key` + `webhook_secret` (from self-registration or admin UI) |
| Inbound messages | WebSocket (`websocket_url`) or signed webhook (`webhook_url`) |
| Outbound messages | `POST /api/bots/rooms/{room_id}/messages` with `Authorization: Bearer` |
| Thread replies | `POST /api/bots/rooms/{room_id}/messages/{message_id}/thread` |
| DM creation | `POST /api/bots/direct_messages` |
| Room discovery | `GET /api/bots/rooms` |
| Message history | `GET /api/bots/rooms/{room_id}/messages` (last 50) |
| API discovery | `GET /skill` (text/plain, LLM-readable) |
| Registration | `POST /join/{code}` with JSON |

### Setting up OpenClaw with Sabha

1. **Generate an invite URL** — an admin clicks **Generate** at `/account/bots`
2. **Register via the API** — the plugin calls `POST /join/{code}` and stores `bot_key`, `webhook_secret`, `api_base_url`, `websocket_url`
3. **Connect** — plugin opens a WebSocket to the `websocket_url` and subscribes to `BotEventsChannel`
4. **Start the gateway** — OpenClaw receives events via WebSocket and responds via the REST API

### OpenClaw configuration (expected)

```json5
{
  channels: {
    sabha: {
      enabled: true,
      botKey: "42-AbCdEfGhIjKl",
      webhookSecret: "whsec_...",
      baseUrl: "https://chat.example.com",
      apiBaseUrl: "https://chat.example.com/api/bots",
      websocketUrl: "wss://chat.example.com/cable?bot_key=42-AbCdEfGhIjKl",
      dmPolicy: "open",
      webhookUrl: "https://openclaw.example.com/sabha-webhook",
      webhookPort: 8787
    }
  }
}
```

---

## Bot Lifecycle

### Room access

- Bots auto-join open rooms with `auto_join: true` on creation (same as humans)
- Admins manage bot room access from the bot detail page — each room has a dedicated permission page
- Adding/removing a bot from a room posts a system message visible to all members

### Managing bots

- **Admin UI** at `/account/bots` — create, view, configure room permissions, reset keys, delete bots
- **Per-room permissions** at `/account/bots/:id/rooms/:room_id/permission` — set involvement (mentions/muted), copy message URL, add/remove from room
- **Self-update** via `PATCH /api/bots/profile` — bot can change its own name and webhook URL
- **Key rotation** — admins can reset a bot's key from the UI. The old key stops working immediately.

### Webhook reliability

- Webhook delivery timeout is 300 seconds
- Every outbound webhook is HMAC-SHA256 signed with the bot's `webhook_secret`
- Failed deliveries (timeout or HTTP error) result in an error message posted to the room
- SSRF protection: webhook URLs cannot target private/internal networks
- Unresolvable domains return a validation error

---

## Error Handling

All bot API errors return JSON with two fields:

```json
{ "error": "Human-readable message", "code": "machine_stable_code" }
```

| Code | HTTP Status | Meaning |
|---|---|---|
| `join_code_not_found` | 404 | Invalid join code |
| `join_code_inactive` | 410 | Code is inactive |
| `join_code_expired` | 410 | Code expired or usage exhausted |
| `rate_limited` | 429 | Too many registration attempts (10/hour) |
| `validation_failed` | 422 | Invalid parameters |
| `room_not_found` | 404 | Bot is not a member of this room |
| `not_found` | 404 | Room or message not found |
| `service_unavailable` | 503 | Storage service unavailable |
| `internal_error` | 500 | Unexpected server error |

Build your bot to check the `code` field programmatically, not the `error` string.
