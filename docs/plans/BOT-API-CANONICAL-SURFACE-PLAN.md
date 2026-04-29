# Bot API canonical surface

**Status:** Proposed (2026-04-29).
**Area:** Bot API (`/api/bots`).
**Scope:** Remove duplicate route shapes, retire the `/thread` endpoint, and tighten controller code paths now that no production consumers depend on the current surface.

## Why

The bot API has accreted parallel shapes for the same operations:

- room-scoped mutation routes (`PATCH /rooms/:room_id/messages/:id`) **and** id-only mutation routes (`PATCH /messages/:id`)
- the dedicated thread endpoint (`POST /rooms/:room_id/messages/:message_id/thread`) **and** inline thread-reply (`POST /rooms/:room_id/messages?parent_message_id=:id`)
- room-scoped reads (`GET /rooms/:room_id/messages/:id`, `GET /rooms/:room_id/messages/:message_id/boosts`) **and** their id-only counterparts have not yet been added but are required for shape consistency

Each pair was introduced as a "permanent alias" because the prevailing constraint was *strictly additive, no breaking changes*. That constraint exists to protect production consumers. There are none — the only client (`openclaw-sabha`) is pre-production. This is the cheapest moment in the API's life to commit to one canonical shape, delete the redundant ones, and ship a tight surface for the public release.

Carrying both shapes forever would mean:
- 33 routes (target: ~23) and the test surface that comes with them
- two doctrinal answers to "how do I edit a message?" in every doc and every code review
- two failure modes for every reshape (new shape works on path A but not path B)
- compounding maintenance cost on every future PR that touches messages or boosts

## Canonical surface (post-cleanup)

### Reads
- `GET /api/bots/rooms` — list rooms
- `GET /api/bots/rooms/:room_id/messages` — list messages in room (paginated, room-scoped because listing is per-room)
- `GET /api/bots/messages/:id` — show single message *(reshaped from `/rooms/:room_id/messages/:id`)*
- `GET /api/bots/messages/:message_id/boosts` — boost aggregation *(reshaped from `/rooms/:room_id/messages/:message_id/boosts`)*
- `GET /api/bots/users`, `/users/:id`, `/autocompletable/users`, `/search` — unchanged

### Mutations
- `POST /api/bots/rooms/:room_id/messages` — create. Optional `?parent_message_id=:id` for thread-reply (returns the resolved thread room id in the body). Always returns `{ id, room_id }`.
- `PATCH /api/bots/messages/:id` — edit own message
- `DELETE /api/bots/messages/:id` — delete own message
- `POST /api/bots/messages/:message_id/boosts` — react
- `DELETE /api/bots/messages/:message_id/boosts/:id` — unreact
- `POST /api/bots/rooms`, `PATCH /:id`, `DELETE /:id` — room CRUD
- `POST /DELETE /api/bots/rooms/:room_id/membership` — bot join/leave
- `POST /DELETE /api/bots/rooms/:room_id/members[/:id]` — admin member management
- `POST /api/bots/direct_messages`, `PATCH /api/bots/profile` — DM start, profile update

**Principle:** URLs encode the minimum context the server can't infer.
- *Creation* needs a target room → `:room_id` in the path.
- *Mutation/aggregation* of an existing record can resolve the room from the record itself → id-only.
- *Listing* is inherently per-room → room-scoped.

## Deletions (no migration, no aliases)

| Route | Replacement |
|---|---|
| `POST /rooms/:room_id/messages/:message_id/thread` | `POST /rooms/:room_id/messages?parent_message_id=:msg_id` |
| `PATCH /rooms/:room_id/messages/:id` | `PATCH /messages/:id` |
| `DELETE /rooms/:room_id/messages/:id` | `DELETE /messages/:id` |
| `POST /rooms/:room_id/messages/:message_id/boosts` | `POST /messages/:message_id/boosts` |
| `DELETE /rooms/:room_id/messages/:message_id/boosts/:id` | `DELETE /messages/:message_id/boosts/:id` |
| `GET /rooms/:room_id/messages/:id` | `GET /messages/:id` |
| `GET /rooms/:room_id/messages/:message_id/boosts` | `GET /messages/:message_id/boosts` |

Net: 7 routes deleted. The `messages/threads_controller.rb` controller is deleted entirely. `messages_controller.rb` and `messages/boosts_controller.rb` shrink because conditional dual-path lookups become single-path.

## Bundled cleanups

1. **Always-on `{ id, room_id }` response on `POST /messages`.** The body-only-when-`parent_message_id` asymmetry from Phase 2 exists only to preserve the empty-body 201 for callers that didn't opt in. With no migration, drop the conditional and always return `{ id, room_id }`. One response shape, simpler controller, simpler test.
2. **Drop `before_action :set_room, if: -> { request.path_parameters[:room_id].present? }` gate.** With room-scoped mutation routes gone, `set_room` only runs for actions that have `:room_id` in the path. The gate becomes vestigial.
3. **Collapse `set_own_message` and `set_room_and_message` to single-path lookups.** No more `if @room … else …` branches.
4. **Envelope/status consistency audit.** Every *controller-level* error returns `{ error, code }` with consistent strings. The previous PR removed one `not_found` override; sweep the remaining 13 controllers for analogous drift. **Carve-out:** requests hitting deleted routes are 404'd by the Rails router *before* reaching `BaseController`, so they bypass `rescue_from ActiveRecord::RecordNotFound` and return the framework's default 404 (HTML in dev, `public/404.html` in prod), not the bot API envelope. This is acceptable because the deleted routes have no remaining production callers and the plugin already treats unknown 4xx responses as generic `SabhaApiError`. Document this asymmetry in `BOT_INTEGRATION.md`'s error table so plugin authors don't expect `{ error, code: "not_found" }` for retired URLs.
5. **`messages_url` envelope field stays.** Still useful for creation (which is room-scoped). The discovery-contract paragraph in `BOT_INTEGRATION.md` already explains why id-only paths don't have a server-provided URL.

## Implementation units

### 1. Routes
- Delete the `resource :thread, only: :create` line.
- Drop `update`, `destroy`, `show` from the room-scoped messages resource (keep `index`, `create`).
- Drop `index`, `create`, `destroy` from the room-scoped boosts resource (delete the resource entirely; boosts move to id-only).
- Expand the id-only block so it covers `show` and the boost surface:
  ```ruby
  resources :messages, only: %i[show update destroy] do
    resources :boosts, only: %i[index create destroy], module: :messages
  end
  ```

### 2. Controllers
- Delete `app/controllers/api/bots/messages/threads_controller.rb`.
- `MessagesController`:
  - Replace `before_action :set_room, if: -> { request.path_parameters[:room_id].present? }` with `before_action :set_room, only: %i[index create]`. The remaining actions (`show`, `update`, `destroy`) are id-only; dropping the gate entirely would make `set_room` run on them with `params[:room_id]` nil and 404.
  - Drop the conditional in `set_own_message` — `@room` is now always nil for `update`/`destroy`, so the lookup collapses to `Message.active.where(room_id: Current.user.rooms.select(:id)).find(params[:id])`.
  - Drop the conditional response shape in `create`. **Keep the `location: room_message_url(...)` argument** so the `Location` header is still emitted alongside the body — `openclaw-sabha`'s `parseSendResponse` reads Location for no-parent sends, and removing it would silently break the plugin's no-parent path.
  - Rewrite `show` — currently `@room.messages.active.with_rich_text_body_and_embeds.with_creator.with_attached_attachment.find(params[:id])`. Once `show` is reached only via id-only routing, `@room` is nil and the action crashes. Mirror the `set_own_message` else-branch shape: `Message.active.where(room_id: Current.user.rooms.select(:id)).with_rich_text_body_and_embeds.with_creator.with_attached_attachment.find(params[:id])`.
- `Messages::BoostsController`:
  - Drop the conditional in `set_room_and_message` — collapses to the id-only lookup (`Message.active.where(room_id: Current.user.rooms.select(:id)).find(params[:message_id])` and `@room = @message.room`).
  - `index` body is unchanged but is now reached only via id-only routing; the lookup collapse above is what makes that work.
  - `create`/`destroy` action bodies unchanged.

### 3. Tests
- Delete `test/controllers/api/bots/messages/threads_controller_test.rb`.
- `creates_test.rb` — drop the regression-pin "no body when no parent_message_id" test (we're committing to body-on always).
- `edits_test.rb`, `deletions_test.rb`, `boosts_controller_test.rb` — drop room-scoped variants of the tests; the id-only variants stay as the only coverage. Keep the "stray `?room_id=` query is ignored" tests as defense-in-depth — they still exercise that the path-params gate is correct (now redundant but cheap).
- Actually, with the gate removed, those tests become trivially uninteresting (no gate to fool). Delete them.
- Move "succeeds for thread message via id-only" tests into the id-only suite as the primary thread regression coverage.

### 4. Documentation
- `docs/features/BOT_INTEGRATION.md` — remove the room-scoped mutation rows from the endpoint table and the alongside-curl-examples for them. Remove the dedicated `/thread` endpoint section. Inline thread-reply (already documented) becomes the only thread-create story. The discovery-contract paragraph stays.
- `app/views/skills/show.text.erb` — same. Both docs stay separate per current decision (`/skill` is the LLM-readable view; `BOT_INTEGRATION.md` is the human-readable view).

### 5. Webhook and `/skill` payload sanity
- Audit `messages_url`-like fields in registration / webhook payloads. The bot creation response includes a `messages_url` per room → stays. Anything that pointed at `/rooms/:room_id/messages/:id` for a single message → check whether it's emitted anywhere; reshape to id-only.

## Test strategy

After each implementation unit, run `bin/rails test test/controllers/api/bots/`. Tests that hit deleted routes will fail loudly — that's the signal to delete them. By the end:
- one PATCH path, one DELETE path, one boost-create path, one boost-destroy path
- one thread-reply path (`?parent_message_id=`)
- one show path, one boost-aggregation path
- counter-test that the deleted routes return 404 (Rails router default; no controller code needed). The test asserts status only — body is the framework default (HTML), not the bot API envelope, per the carve-out in cleanup #4.

## Risks

### Plugin impact (verified against `openclaw-sabha/docs/SERVER-API-USAGE.md`)

The plugin already migrated to id-only mutations and `parent_message_id` in `b67fc38` / `e2be713` / `dea690a`. Cross-referencing this PR's deletions against the plugin's documented surface gives a precise impact:

**Required plugin migration — one method, ~5 lines.**

| Server change | Plugin caller | Fix |
|---|---|---|
| Delete `GET /rooms/:room_id/messages/:message_id/boosts` (boost aggregation reshape to id-only) | `client.listReactions(roomId, messageId)` (`src/client.ts:265`) | Drop the `roomId` argument; switch URL to `GET /messages/:message_id/boosts`. The plugin doc itself notes this is "the one read endpoint that is still room-scoped — id-only would be welcome but not required." |

**Optional plugin simplification — one method, ~10 lines.**

| Server change | Plugin caller | Status |
|---|---|---|
| Always-on `{ id, room_id }` body on `POST /messages` | `parseSendResponse` (`src/client.ts:161`) | **Non-breaking.** Plugin currently reads `Location` header for no-parent sends, JSON body for `parent_message_id` sends. With body always present, no-parent path keeps reading Location and ignores the new body — plugin's own refactor flag #3 confirms this is silent drift, not a break. Plugin can collapse to "always read body" at its own pace. |

**Already migrated — invisible to the plugin.**

All other deletions in this PR (`/thread` endpoint, room-scoped PATCH/DELETE, room-scoped boost POST/DELETE, `GET /rooms/:room_id/messages/:id`) hit code paths the plugin no longer uses. Plugin doc Section 12 enumerates these as "What the plugin does **not** use (so a refactor here is invisible to us)."

**Sequence:**
1. Server PR ships the new surface, deletes the old.
2. Plugin PR ships the `listReactions` migration (required) and optionally the `parseSendResponse` simplification.
3. Plugin GA + bot API public release happen together.

If the plugin lags step 2, `listReactions` calls fail loudly with 404. That's the right failure mode — better than silent dual-path drift.

### Don't reshape boost-aggregation field names in this PR

The plugin doc suggests renaming `reactions[].content` → `name` and `reactions[].boosters` → `users` server-side would let the plugin drop a projection layer. **Don't do this here.** It's a wire-shape change beyond the route cleanup's scope and would need its own plugin-side migration. Bundle it with a separate field-rename PR if/when we want it.

### `/skill` payload changes shape
The `/skill` endpoint serves a plain-text doc consumed by LLMs. After this PR, the document changes. Any downstream tool that has cached or fingerprinted the previous doc will see an updated body. No semantic risk; flagging only because the LLM-readable surface is itself part of the contract.

### Test invariants from removed paths
Some tests today assert side effects like `notify_bots` / broadcast counts on the room-scoped paths. Those signals are now exercised on the id-only paths. Migrate the assertions; don't lose them.

## Exit criteria

- 33 → 27 routes inside `/api/bots` (verified via `bin/rails routes | grep api/bots | wc -l`). The "23 canonical surface ops" in the appendix counts unique HTTP method+path tuples; `bin/rails routes` lists PATCH and PUT as separate aliases, hence the 27. Net delta: −8 (POST `/thread`, PATCH/PUT/DELETE for room-scoped messages, GET single, GET/POST/DELETE room-scoped boosts) + 2 (GET `/messages/:id`, GET `/messages/:message_id/boosts`).
- `messages/threads_controller.rb` deleted; `messages_controller.rb` and `messages/boosts_controller.rb` no longer have dual-path conditionals
- `BOT_INTEGRATION.md` and `app/views/skills/show.text.erb` describe one shape per operation
- Bot API test suite green; rubocop clean
- The plugin migration PR is open (or linked from this PR's description) so reviewers can see the receiving end

## Out of scope

- **Changes to non-mutating bot endpoints** (rooms, users, search, profile, DMs, members) beyond consistency cleanup. They already follow the canonical shape.
- **Single doc source** (collapsing `BOT_INTEGRATION.md` and `skills/show.text.erb` into one file). Decision: keep two docs; LLM and human audiences benefit from different framing.
- **Webhook payload reshape.** Webhook events deliver bot-relevant context; their shape is independent of the HTTP route surface. If a future plan reshapes webhooks, it's separate.
- **Pre-existing `Rooms::Thread.find_or_create_for` race.** Documented in the prior plan; not introduced or fixed here.

## Appendix: post-cleanup server↔bot interface

After this PR, the bot ↔ server contract has **three surfaces** — two for inbound (server → bot) and one for outbound (bot → server). Auth and event payloads are shared across all three.

### Auth (one secret, two transports)

- **HTTP:** `Authorization: Bearer <bot_key>` on every request.
- **WebSocket:** `wss://host/cable?bot_key=<bot_key>` (header injection isn't reliable in browser/native WS clients).
- **Webhooks:** payload signed `HMAC-SHA256(webhook_secret, body)` in an `X-Sabha-Signature` header. The bot verifies on receipt.

### Inbound: server → bot (push)

The bot can use **either or both** of two delivery channels — selected at registration time and changeable later via `PATCH /profile`:

- **WebSocket (`BotEventsChannel`).** Bot opens an outbound connection. No port forwarding, no public URL.
- **Webhook.** Bot has a public URL; server POSTs HMAC-signed payloads when events fire. The webhook may reply with a body, which Sabha auto-posts as the bot's response (the "bash one-liner bot" pattern).

When both are configured, every event is delivered via both channels — the bot is responsible for deduplication (use `X-Sabha-Delivery` from the webhook headers).

Both deliver the **same event payload** (`Bot::EventPayload`). Events:

| Event | Fires on | Payload shape |
|---|---|---|
| `message_created` | New message in any room the bot is a member of (per-room mention rules apply for open/closed rooms; threads/DMs deliver every message) | `{ event, user, room, message }` |
| `message_updated` | Edit | same |
| `message_deleted` | Soft-delete | same |
| `boost_created` | Reaction added | `{ event, user, room, message, boost }` |
| `boost_deleted` | Reaction removed | same |
| `user_created` / `user_updated` / `user_deleted` | User lifecycle (only delivered to bots that opted in) | `{ event, user }` |

**Payload sub-shapes** (canonical, not changed by this cleanup):

- `user`: `{ id, name, role, bot, url }`
- `room`: `{ id, name, type, members, has_bot, messages_url }`
- `message`: `{ id, body: { html, plain }, has_attachment, attachment, mentionees, created_at, thread? }`

`messages_url` on each `room` is the **only server-provided URL** in the payload. Everything else (single-message URLs, boost URLs, etc.) is derived from `api_base_url` per the discovery contract.

### Outbound: bot → server (HTTP API)

The 23 canonical routes after cleanup, grouped by what the bot is doing:

```
─ Send / react ──────────────────────────────────
POST   /rooms/:room_id/messages                   # post (optional ?parent_message_id=)
PATCH  /messages/:id                              # edit own message
DELETE /messages/:id                              # delete own message
POST   /messages/:message_id/boosts               # react
DELETE /messages/:message_id/boosts/:id           # unreact

─ Read ──────────────────────────────────────────
GET    /rooms                                     # list rooms bot is in
GET    /rooms/:room_id/messages                   # paginated history (cursor)
GET    /messages/:id                              # single message
GET    /messages/:message_id/boosts               # boost aggregation
GET    /search?q=...                              # message search
GET    /users, /users/:id, /autocompletable/users # user discovery

─ Membership ────────────────────────────────────
POST   /rooms/:room_id/membership                 # bot self-joins an open room
DELETE /rooms/:room_id/membership                 # bot self-leaves
POST   /rooms/:room_id/members                    # admin: add a user
DELETE /rooms/:room_id/members/:id                # admin: remove a user

─ DMs and rooms ─────────────────────────────────
POST   /direct_messages                           # start/resume a DM
POST   /rooms                                     # create room
PATCH  /rooms/:id                                 # update
DELETE /rooms/:id                                 # archive

─ Self ──────────────────────────────────────────
PATCH  /profile                                   # update bot profile
```

### Mental model the bot author holds

- **"Where does this op need a `:room_id`?"** Only when the server can't infer it: creation needs a target; listing is per-room; membership/admin acts on a room. Everything else is id-only.
- **"How do I reply in a thread?"** `POST /rooms/:parent_room_id/messages?parent_message_id=:msg_id`. The response body tells you the resolved thread `room_id` for any follow-up *listing* you might want; for editing/deleting/reacting, the id-only routes don't care about the room.
- **"How do I receive events?"** Pick WebSocket or webhook at registration. Same payload either way.

### What disappears from the bot's vocabulary

- `/thread` endpoint — never call it; pass `parent_message_id` instead.
- Tracking `roomId` alongside `messageId` for streaming edits — just track `messageId`.
- Any concept of "room-scoped vs id-only" for mutations — there's only id-only.
- Different 404 envelopes from different endpoints — always `{ error: "Not found", code: "not_found" }`.

### What stays the same

- HMAC webhook signing scheme.
- Bearer token auth.
- Event payload shapes (the cleanup is route-only, not event-payload).
- WebSocket channel name and stream tenancy.
- Registration flow (`POST /join/:join_code`).

## References

- `docs/plans/ID-ONLY-BOT-MESSAGE-OPS-PLAN.md` — the PR that introduced id-only mutations and inline thread-reply (#51, merged 2026-04-29). This PR retires the duplicate shapes that PR left in place.
- `app/controllers/api/bots/messages_controller.rb`, `app/controllers/api/bots/messages/boosts_controller.rb`, `app/controllers/api/bots/messages/threads_controller.rb`
- `app/channels/bot_events_channel.rb`, `app/models/bot/event_payload.rb` — real-time and webhook payload shapes (unchanged by this PR)
- `config/routes.rb` (bot namespace block)
- `docs/features/BOT_INTEGRATION.md`, `app/views/skills/show.text.erb`
