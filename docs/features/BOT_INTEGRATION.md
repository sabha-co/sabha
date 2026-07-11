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

A `webhook_secret` is generated for **every** bot at creation, regardless of whether `webhook_url` is set. A bot that starts out WebSocket-only can add a webhook URL later via `PATCH /api/bots/profile` without re-registering — it already holds the secret.

The registration and `PATCH /api/bots/profile` endpoints also accept `mentions_url` and `everything_url` as legacy aliases for `webhook_url`. They map to the same column and are kept for backwards compatibility with older self-hosted bots.

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

> **URL shape principle.** URLs encode the minimum context the server can't infer. *Creating* a message needs a target room, so it's `POST /rooms/{room_id}/messages`. *Listing* is inherently per-room, so it's `GET /rooms/{room_id}/messages`. *Mutating, reading, or aggregating* an existing record can resolve the room from the record itself, so they're id-only: `/messages/{id}`, `/messages/{message_id}/boosts/...`. The id-only endpoints are stable across rooms and tenants — a bot streaming partial edits never has to track room rebinds across thread creates.
>
> **Per-room URLs — server is the source of truth.** Every webhook payload and the registration response include a `messages_url` on each `room` object pointing at the room-scoped messages collection (used for posting and listing). Clients **should** consume that field directly rather than deriving URLs from `api_base_url` + `room_id`. Derivation works today but will silently break if the server's URL shape ever changes (versioning, subdomain split, new `script_name` mount). Treat string concatenation as a compatibility fallback only. Id-only URLs (`/messages/{id}`, `/messages/{message_id}/boosts/...`) have no per-room context to encode and so are not surfaced as discovery fields — derive them from `api_base_url`.

| Action | Method | Endpoint |
|---|---|---|
| Post a message | POST | `/rooms/{room_id}/messages` |
| Send attachment | POST | `/rooms/{room_id}/messages` (multipart) |
| Reply in a thread | POST | `/rooms/{room_id}/messages?parent_message_id={message_id}` |
| Edit own message | PATCH | `/messages/{id}` |
| Delete own message | DELETE | `/messages/{id}` |
| Read single message | GET | `/messages/{id}` |
| Read messages | GET | `/rooms/{room_id}/messages` |
| Add reaction | POST | `/messages/{message_id}/boosts` |
| Remove reaction | DELETE | `/messages/{message_id}/boosts/{id}` |
| List reactions | GET | `/messages/{message_id}/boosts` |
| List room members | GET | `/rooms/{room_id}/members` |
| Add member to room | POST | `/rooms/{room_id}/members` |
| Remove member from room | DELETE | `/rooms/{room_id}/members/{user_id}` |
| Bot joins room | POST | `/rooms/{room_id}/membership` |
| Bot leaves room | DELETE | `/rooms/{room_id}/membership` |
| List users (for mention discovery) | GET | `/users?room_id={room_id}` |
| Look up a user by id | GET | `/users/{user_id}` |
| Autocomplete users by name/handle | GET | `/autocompletable/users?room_id={room_id}&query=...` |
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

### Pagination

Endpoints that return collections of messages use **cursor pagination** with a stable envelope:

```json
{
  "results":     [ /* message objects */ ],
  "has_more":    true,
  "next_cursor": "eyJpZCI6MTIzNDV9"
}
```

Pass `next_cursor` back as `cursor=...` on the next request (or use the typed-cursor params below) until `has_more` is `false`.

| Endpoint | Cursor / filter params |
|---|---|
| `GET /rooms/{room_id}/messages` | `before_id`, `before_time`, `after_time`, `limit` |
| `GET /search` | `room_ids[]`, `author_ids[]`, `before_id`, `before_time`, `after_time`, `limit` |

`GET /rooms` and `GET /users` use **page-based** pagination (`page`, `per_page`). `per_page` defaults to 50 and is capped at 100. `GET /rooms` also accepts `query=` for substring matching on room names.

### Response shapes (overview)

| Endpoint | Status | Body |
|---|---|---|
| `POST /rooms/{id}/messages` | `201` + `Location` | `{ "id": 10, "room_id": 5 }` |
| `POST /rooms/{id}/messages?parent_message_id={pid}` | `201` + `Location` | `{ "id": 10, "room_id": <thread_room_id> }` |
| `PATCH /messages/{id}` | `200` | `{ "id": 10, "body": { "html": "...", "plain": "..." } }` |
| `DELETE /messages/{id}` | `204` | — |
| `POST /messages/{id}/boosts` | `201` | `{ "id": 7, "content": "🎉" }` |
| `GET /messages/{id}/boosts` | `200` | `{ "reactions": [ { "content": "🎉", "count": 3, "boosters": [ {"id":1,"name":"A"}, … ], "truncated": false } ], "total": 5, "truncated": false }` |
| `POST /direct_messages` | `200` (existing DM) or `201` (new) | `{ "room": { "id": 5 } }` |
| `PATCH /profile` | `200` | `{ "name": "MyBot", "webhook_url": "https://..." }` |
| `POST /rooms/{id}/members` | `201` | `{ "id": 42, "name": "Alice" }` |
| `GET /rooms/{id}/members` | `200` | `[ { "id": 1, "name": "Alice", "role": "member" }, … ]` |

**Multipart upload** (file attachments): post `multipart/form-data` to `POST /rooms/{id}/messages` with the file under the field name `attachment`.

```bash
curl -X POST "$API/rooms/$ROOM_ID/messages" \
  -H "Authorization: Bearer $BOT_KEY" \
  -F "attachment=@photo.jpg"
```

---

## Room Permissions

A bot's access to each room is controlled by its membership involvement:

- **Mentions** — bot receives events when @mentioned or in a DM. Applies to both WebSocket and webhook delivery. If `webhook_url` is set, the HTTP response body is auto-posted as a reply.
- **Muted** — bot receives no events from this room. It can still post and read via the API.

Admins configure permissions per room from the bot's detail page. Each room has its own permission page at `/account/bots/:bot_id/rooms/:room_id/permission`. The `mentions` and `nothing` options surface in the UI as **Mentions** and **Muted**; the membership model also accepts `everything` (set via API or console) — a bot with `involvement: :everything` receives every message in the room.

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

`@{user_id}` only resolves against members of the target room — a mention to a user not in `room_id` is silently dropped. To find user ids, use the discovery endpoints (next section) and **always pass `room_id` matching the room you'll post in**.

### Discovering users

To resolve a name to a `user_id` for mentioning:

```bash
curl "$API/autocompletable/users?room_id=$ROOM_ID&query=alice" \
  -H "Authorization: Bearer $BOT_KEY"
```

Returns up to 20 users matching the query (exact first-name matches ranked first). Each result has `id`, `name`, `role`, `bot`, and `url`.

To list all users in a room (paginated):

```bash
curl "$API/users?room_id=$ROOM_ID&page=1&per_page=50" \
  -H "Authorization: Bearer $BOT_KEY"
```

Defaults to `per_page=50` (max `100`). Omit `room_id` to span all rooms the bot shares — useful for directory browsing, but results may include users not mentionable from any single room.

To fetch a single user's full profile (bio, social URLs):

```bash
curl "$API/users/$USER_ID" -H "Authorization: Bearer $BOT_KEY"
```

All three endpoints exclude default-named placeholder accounts and deactivated users. With `room_id`, the bot must be a member of that room or the request returns `404`.

### Editing a message

Bots can edit their own messages. The request body replaces the message content.

```bash
curl -X PATCH "$API/messages/$MESSAGE_ID" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: text/plain" \
  -d "Updated: deploy complete (v2.1.0)"
```

### Deleting a message

Bots can delete their own messages (soft-delete).

```bash
curl -X DELETE "$API/messages/$MESSAGE_ID" \
  -H "Authorization: Bearer $BOT_KEY"
```

Returns `204 No Content` on success.

### Adding a reaction

Send the emoji as plain text in the request body.

```bash
curl -X POST "$API/messages/$MESSAGE_ID/boosts" \
  -H "Authorization: Bearer $BOT_KEY" \
  -H "Content-Type: text/plain" \
  -d "🎉"
```

Returns the boost ID which you can use to remove it later.

### Removing a reaction

```bash
curl -X DELETE "$API/messages/$MESSAGE_ID/boosts/$BOOST_ID" \
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

Returns a cursor-paginated envelope (see Pagination above) with matching messages and room context. Filter further with `room_ids[]`, `author_ids[]`, `before_id`, `before_time`, `after_time`, and `limit`.

### Reading a single message

```bash
curl "$API/messages/$MESSAGE_ID" -H "Authorization: Bearer $BOT_KEY"
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

`name` is required and `type` must be `open` or `closed`. Missing or invalid values return `422` with `code: "validation_failed"`.

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

The `role` field is always one of `"member"`, `"moderator"`, `"administrator"`, or `"bot"` — branch on this value if the bot needs to distinguish humans from other bots in the same room. Unlike the autocomplete `users` endpoints (which add a `"bot": true/false` flag for convenience), the webhook payload's `user` object does **not** carry a separate `bot` key — use `role == "bot"` instead.

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

Reply in a thread by adding a `parent_message_id` query parameter to the regular `POST /messages` endpoint:

```
POST /api/bots/rooms/{room_id}/messages?parent_message_id={message_id}
Authorization: Bearer {bot_key}
Content-Type: text/plain

This is a threaded reply!
```

`parent_message_id` is a **query-string parameter**, not part of the body — the request body remains the message text. The server creates the thread room (or finds the existing one), adds the bot as a member, and posts the reply there. The response is `201 Created` with body `{ "id": <message_id>, "room_id": <thread_room_id> }` and a `Location` header pointing at the new message. The `room_id` in the body is the resolved thread room id.

A `parent_message_id` pointing at a message in a different room than `{room_id}` returns 404. A `parent_message_id` pointing at a message that already lives inside a thread returns 422 — Sabha doesn't support nested threads.

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

In SaaS mode the URL also includes the workspace identifier so the connection lands in the right tenant:

```
wss://saas.example.com/cable?bot_key=42-AbCdEfGhIjKl&wid=acme
```

Always use the `websocket_url` returned by the registration response verbatim — don't build it from `base_url`.

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

[OpenClaw](https://openclaw.ai) is an AI agent platform that connects to chat services. The [`openclaw-sabha`](https://github.com/sabha-co/openclaw-sabha) plugin (v0.10.0+) implements the bearer-token auth and HMAC webhook verification documented here.

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
| Thread replies | `POST /api/bots/rooms/{room_id}/messages?parent_message_id={message_id}` |
| DM creation | `POST /api/bots/direct_messages` |
| Room discovery | `GET /api/bots/rooms` |
| Message history | `GET /api/bots/rooms/{room_id}/messages` (last 50) |
| User discovery | `GET /api/bots/autocompletable/users?room_id={id}&query=...` |
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

### Account-level restrictions

Accounts can restrict which users (humans or bots) can create direct messages via the `restrict_direct_messages_to_administrators` setting. When enabled, `POST /api/bots/direct_messages` returns `403 Forbidden` for any non-admin bot. Room creation is restricted the same way via `restrict_room_creation_to_administrators`. Admins toggle these on the account settings page.

### Webhook reliability

- Webhook delivery timeout is 300 seconds
- Every outbound webhook is HMAC-SHA256 signed with the bot's `webhook_secret`
- Failed deliveries (timeout or HTTP error) result in an error message posted to the room
- SSRF protection: webhook URLs cannot target private/internal networks
- Unresolvable domains return a validation error

---

## Error Handling

All bot API errors from existing endpoints return JSON with two fields:

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

**Carve-out: requests to retired URLs.** A request to a path that does not match any current bot API route (e.g. older shapes that have been removed) is 404'd by the Rails router *before* reaching a bot controller, so the response body is the framework default (HTML), not the JSON envelope above. Treat any 404 with a non-JSON body as "URL no longer exists" and update your client.
