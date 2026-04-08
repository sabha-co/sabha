# Bot Integration Guide

Sabha's bot API lets external programs post messages, read conversations, and respond to mentions. This guide covers building simple task bots and connecting AI agents like OpenClaw.

## Quick Start

### 1. Enable bot self-registration

An admin toggles **"Allow bots to self-register via join code"** in account settings (`/account`). This is off by default.

### 2. Get a join code

Admins always have a global join code at `/account`. If "Allow users to create invite links" is enabled, any user can generate one from their profile.

### 3. Register a bot

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
  "name": "My Bot",
  "webhook_url": "https://my-server.com/webhook",
  "websocket_url": "wss://chat.example.com/cable?bot_key=42-AbCdEfGhIjKl",
  "rooms": [
    { "id": 1, "name": "General", "type": "Open",
      "messages_url": "https://chat.example.com/rooms/1/42-AbCdEfGhIjKl/messages" }
  ]
}
```

Store the `bot_key` — it is shown only once. It authenticates all subsequent API calls.

The bot is automatically added to all open rooms marked as auto-join, just like a human user.

### 4. Alternatively: create a bot via admin UI

Admins can create bots at `/account/bots` without needing self-registration enabled. The admin sets the name, webhook URL, and manages the bot key from the UI.

---

## API Reference

All endpoints authenticate via `bot_key` in the URL path. The bot key is a secret — always use HTTPS.

| Action | Method | Endpoint |
|---|---|---|
| Post a message | POST | `/rooms/{room_id}/{bot_key}/messages` |
| Send attachment | POST | `/rooms/{room_id}/{bot_key}/messages` (multipart) |
| Edit own message | PATCH | `/rooms/{room_id}/{bot_key}/messages/{id}` |
| Delete own message | DELETE | `/rooms/{room_id}/{bot_key}/messages/{id}` |
| Read single message | GET | `/rooms/{room_id}/{bot_key}/messages/{id}` |
| Reply in a thread | POST | `/rooms/{room_id}/{bot_key}/messages/{message_id}/thread` |
| Read messages | GET | `/rooms/{room_id}/{bot_key}/messages` |
| Add reaction | POST | `/rooms/{room_id}/{bot_key}/messages/{message_id}/boosts` |
| Remove reaction | DELETE | `/rooms/{room_id}/{bot_key}/messages/{message_id}/boosts/{boost_id}` |
| List room members | GET | `/rooms/{room_id}/{bot_key}/members` |
| Add member to room | POST | `/rooms/{room_id}/{bot_key}/members` |
| Remove member from room | DELETE | `/rooms/{room_id}/{bot_key}/members/{user_id}` |
| Bot joins room | POST | `/rooms/{room_id}/{bot_key}/membership` |
| Bot leaves room | DELETE | `/rooms/{room_id}/{bot_key}/membership` |
| Search messages | GET | `/{bot_key}/search?q=query` |
| List rooms | GET | `/rooms/{bot_key}` |
| List joinable rooms | GET | `/rooms/{bot_key}?joinable=true` |
| Create room | POST | `/rooms/{bot_key}` |
| Update room | PATCH | `/rooms/{room_id}/{bot_key}` |
| Archive room | DELETE | `/rooms/{room_id}/{bot_key}` |
| Create a DM | POST | `/rooms/{bot_key}/directs` |
| Update bot settings | PATCH | `/bots/{bot_key}` |
| API discovery | GET | `/skill` (unauthenticated) |

The `/skill` endpoint returns a plain-text document describing the full API with examples. It is designed to be readable by both humans and LLMs.

---

## Room Permissions

A bot's access to each room is controlled by its membership involvement:

- **Mentions** — webhook fires when @mentioned or in a DM. Response is auto-posted as a reply.
- **Muted** — no webhooks. Bot can still post and read via the API.

Admins configure permissions per room from the bot's detail page. Each room has its own permission page at `/account/bots/:id/rooms/:room_id/permission`.

By default, new bots join open rooms with "mentions" involvement.

---

## Simple Task Bots

For small automations — deploy notifications, CI alerts, standup reminders — you only need to POST messages. No webhook server required.

### Deploy notifier (bash)

```bash
BOT_KEY="42-AbCdEfGhIjKl"
ROOM_ID=1
BASE_URL="https://chat.example.com"

curl -X POST "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/messages" \
  -H "Content-Type: text/plain" \
  -d "Deploy complete: $(git log --oneline -1)"
```

### Scheduled reminder (cron)

```bash
# Every weekday at 9am
0 9 * * 1-5 curl -X POST "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/messages" \
  -H "Content-Type: text/plain" \
  -d "Standup time! What are you working on today?"
```

### GitHub webhook forwarder (Ruby)

A small Sinatra app that receives GitHub webhooks and posts to Sabha:

```ruby
require "sinatra"
require "net/http"
require "json"

BOT_KEY  = ENV["SABHA_BOT_KEY"]
ROOM_ID  = ENV["SABHA_ROOM_ID"]
BASE_URL = ENV["SABHA_URL"]

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
    uri = URI("#{BASE_URL}/rooms/#{ROOM_ID}/#{BOT_KEY}/messages")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.post(uri.path, message, "Content-Type" => "text/plain")
    end
  end

  status 200
end
```

### Mentioning users

Use `@{user_id}` syntax in message bodies:

```bash
curl -X POST "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/messages" \
  -H "Content-Type: text/plain" \
  -d "Hey @{42}, your build failed."
```

### Editing a message

Bots can edit their own messages. The request body replaces the message content.

```bash
curl -X PATCH "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/messages/$MESSAGE_ID" \
  -H "Content-Type: text/plain" \
  -d "Updated: deploy complete (v2.1.0)"
```

### Deleting a message

Bots can delete their own messages (soft-delete).

```bash
curl -X DELETE "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/messages/$MESSAGE_ID"
```

Returns `204 No Content` on success.

### Adding a reaction

Send the emoji as plain text in the request body.

```bash
curl -X POST "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/messages/$MESSAGE_ID/boosts" \
  -H "Content-Type: text/plain" \
  -d "🎉"
```

Returns the boost ID which you can use to remove it later.

### Removing a reaction

```bash
curl -X DELETE "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/messages/$MESSAGE_ID/boosts/$BOOST_ID"
```

### Listing room members

```bash
curl "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/members"
```

Returns an array of members with `id`, `name`, and `role` (member, moderator, administrator, or bot).

### Searching messages

Search across all rooms the bot is a member of.

```bash
curl "$BASE_URL/$BOT_KEY/search?q=deploy"
```

Returns up to 50 matching messages with room context.

### Reading a single message

```bash
curl "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/messages/$MESSAGE_ID"
```

Returns the message with creator, body, attachment, and mentionees.

### Discovering joinable rooms

List open rooms the bot can join (rooms it's not already in).

```bash
curl "$BASE_URL/rooms/$BOT_KEY?joinable=true"
```

### Joining a room

Bots can join any open room.

```bash
curl -X POST "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/membership"
```

Returns the room object on success (201).

### Leaving a room

```bash
curl -X DELETE "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/membership"
```

Returns `204 No Content`. Cannot leave direct message rooms.

### Creating a room

Bots can create open or closed rooms. The bot is auto-joined and recorded as the creator.

```bash
curl -X POST "$BASE_URL/rooms/$BOT_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "Bot Room", "type": "open"}'
```

### Updating a room

Only the bot that created the room can update it.

```bash
curl -X PATCH "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "New Name"}'
```

### Archiving a room

Only the bot that created the room can archive it (soft-delete).

```bash
curl -X DELETE "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY"
```

Returns `204 No Content`.

### Adding a member to a room

Only the bot that created the room can manage members.

```bash
curl -X POST "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/members" \
  -H "Content-Type: application/json" \
  -d '{"user_id": 42}'
```

### Removing a member from a room

```bash
curl -X DELETE "$BASE_URL/rooms/$ROOM_ID/$BOT_KEY/members/$USER_ID"
```

Returns `204 No Content`.

---

## Interactive Bots (Webhook-Driven)

Register a `webhook_url` when creating a bot. Sabha calls it when someone @mentions the bot or DMs it.

### How it works

1. User sends: "Hey @MyBot, what's the weather?"
2. Sabha POSTs to the bot's `webhook_url` with the message payload
3. The bot's HTTP response body is automatically posted as a reply

No second API call needed. Just return text.

### Webhook payload

All URLs in the payload are absolute — you can call them directly.

```json
{
  "event": "message_created",
  "user": { "id": 1, "name": "Alice", "role": "member", "url": "https://chat.example.com/users/1" },
  "room": {
    "id": 5, "name": "General", "type": "Open",
    "members": 12, "has_bot": true,
    "messages_url": "https://chat.example.com/rooms/5/42-AbCdEfGhIjKl/messages"
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
POST /rooms/{room_id}/{bot_key}/messages/{message_id}/thread
Content-Type: text/plain

This is a threaded reply!
```

This creates a thread on the message (or finds an existing one) and posts the reply there.

### Minimal echo bot (Ruby)

```ruby
require "sinatra"
require "json"

post "/webhook" do
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
4. Events arrive as JSON — same payload format as webhooks

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

Events arrive as JSON messages with the same structure as webhook payloads:

```json
{
  "event": "message_created",
  "user": { "id": 1, "name": "Alice", "role": "member", "url": "..." },
  "room": { "id": 5, "name": "General", "type": "Open", "members": 12, "has_bot": true, "messages_url": "..." },
  "message": { "id": 10, "body": { "html": "...", "plain": "..." }, "mentionees": [...], "created_at": "...", "updated_at": "..." }
}
```

All event types are supported: `message_created`, `message_updated`, `message_deleted`, `boost_created`, `boost_deleted`, `user_created`, `user_deleted`.

### Sending replies

WebSocket is receive-only. To reply, use the REST API:

```bash
curl -X POST "https://chat.example.com/rooms/$ROOM_ID/$BOT_KEY/messages" \
  -H "Content-Type: text/plain" \
  -d "Got your message!"
```

### Webhooks as fallback

Bots can use both connection modes simultaneously. If a `webhook_url` is configured, Sabha delivers events via both WebSocket and webhook. The bot client is responsible for deduplication.

To use webhooks only, ignore the `websocket_url` from registration. To use WebSocket only, register without a `webhook_url`.

### Reconnection

Bots should implement reconnection with exponential backoff. Sabha's AnyCable server supports connection state caching — brief disconnects (under 5 minutes) restore cleanly.

---

## OpenClaw Integration

[OpenClaw](https://openclaw.ai) is an AI agent platform that connects to chat services. Sabha's bot API maps naturally to OpenClaw's channel plugin architecture.

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
                                       REST API POST
                                              |
                                              v
                                    Sabha receives reply
```

**Webhook mode (fallback):**

```
User @mentions bot in Sabha
        |
        v
Sabha calls webhook_url ──> OpenClaw gateway receives event
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

For proactive messages (not in response to a mention), OpenClaw calls Sabha's REST API directly.

### How Sabha maps to OpenClaw concepts

| OpenClaw concept | Sabha equivalent |
|---|---|
| Channel | Sabha bot API |
| Bot token | `bot_key` (from self-registration or admin UI) |
| Inbound messages | WebSocket (`websocket_url`) or webhook (`webhook_url`) |
| Outbound messages | `POST /rooms/{room_id}/{bot_key}/messages` (or webhook response body in webhook mode) |
| Thread replies | `POST /rooms/{room_id}/{bot_key}/messages/{message_id}/thread` |
| DM creation | `POST /rooms/{bot_key}/directs` |
| Room discovery | `GET /rooms/{bot_key}` |
| Message history | `GET /rooms/{room_id}/{bot_key}/messages` (last 50) |
| API discovery | `GET /skill` (text/plain, LLM-readable) |
| Registration | `POST /join/{code}` with JSON (like BotFather for Telegram) |

### Setting up OpenClaw with Sabha

1. **Enable self-registration** in Sabha admin settings
2. **Get a join code** from `/account`
3. **Register via the API** — OpenClaw's Sabha channel plugin calls `POST /join/{code}` to get a `bot_key` and `websocket_url`
4. **Connect** — plugin opens a WebSocket to the `websocket_url` and subscribes to `BotEventsChannel`
5. **Start the gateway** — OpenClaw receives events via WebSocket and responds via REST API

### OpenClaw configuration (expected)

```json5
{
  channels: {
    sabha: {
      enabled: true,
      baseUrl: "https://chat.example.com",
      botKey: "42-AbCdEfGhIjKl",        // from self-registration
      dmPolicy: "open",
      webhookUrl: "https://openclaw.example.com/sabha-webhook",
      webhookPort: 8787
    }
  }
}
```

### Key differences from other OpenClaw channels

- **WebSocket and webhook** — Sabha supports both. WebSocket mode (like Mattermost) lets the bot connect outbound with no tunnel needed. Webhook mode (like Telegram) is available as a fallback.
- **Reply-by-response** — in webhook mode, the HTTP response body IS the reply. In WebSocket mode, replies go through the REST API.
- **Thread support** — POST to `messages/{id}/thread` for threaded replies.
- **Bot key in URL path** — not a header. OpenClaw's HTTP client needs to embed the key in request URLs rather than using `Authorization` headers.

---

## Bot Lifecycle

### Room access

- Bots auto-join open rooms with `auto_join: true` on creation (same as humans)
- Admins manage bot room access from the bot detail page — each room has a dedicated permission page
- Adding/removing a bot from a room posts a system message visible to all members

### Managing bots

- **Admin UI** at `/account/bots` — create, view, configure room permissions, reset keys, delete bots
- **Per-room permissions** at `/account/bots/:id/rooms/:room_id/permission` — set involvement (mentions/muted), copy message URL, add/remove from room
- **Self-update** via `PATCH /bots/{bot_key}` — bot can change its own name and webhook URL
- **Key rotation** — admins can reset a bot's key from the UI. The old key stops working immediately.

### Webhook reliability

- Webhook delivery timeout is 300 seconds
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
| `self_registration_disabled` | 403 | Account setting is off |
| `rate_limited` | 429 | Too many registration attempts (10/hour) |
| `validation_failed` | 422 | Invalid parameters |
| `room_not_found` | 404 | Bot is not a member of this room |
| `not_found` | 404 | Room or message not found |
| `service_unavailable` | 503 | Storage service unavailable |
| `internal_error` | 500 | Unexpected server error |

Build your bot to check the `code` field programmatically, not the `error` string.
