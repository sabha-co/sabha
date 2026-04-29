# Bot API simplification: id-only message ops + inline thread-reply

**Status:** Proposed (2026-04-29).
**Area:** Bot API (`/api/bots`).
**Scope:** Additive endpoints; no data-model changes; no breaking changes to existing endpoints.

This plan is split into two phases:

- **Phase 1 — id-only mutating endpoints.** Eliminates the mid-stream room rebind in streaming clients. Stand-alone, ships independently.
- **Phase 2 (conditional) — inline thread-reply via `parent_message_id` on POST.** Pure ergonomic improvement. Decision deferred until after Phase 1 ships and we see whether the remaining two-step thread-create flow is still felt as friction by clients.

Phase 1 is the load-bearing change. Phase 2 is reviewed below for completeness so the option is documented, not because we've committed to it.

---

# Phase 1 — id-only message ops

## Why

The current bot API requires a `room_id` in the URL for every mutating message op:

```
PATCH  /api/bots/rooms/:room_id/messages/:id
DELETE /api/bots/rooms/:room_id/messages/:id
POST   /api/bots/rooms/:room_id/messages/:message_id/boosts
DELETE /api/bots/rooms/:room_id/messages/:message_id/boosts/:id
```

That coupling is fine when a bot already knows which room its message lives in. It becomes a problem in **streaming reply flows**, because Sabha threads are modeled as separate `Rooms::Thread` records (STI subtype of `Room`, `app/models/rooms/thread.rb`). When a bot replies in a thread for the first time, `POST /rooms/:room_id/messages/:message_id/thread` (`app/controllers/api/bots/messages/threads_controller.rb`) creates a *new* room and posts the first message there. Every subsequent edit to that message must target the new room, not the parent.

For non-streaming clients this is invisible: they read the thread room id once from the response and use it. For streaming clients (the Sabha OpenClaw plugin's draft-stream loop, `extensions/sabha/src/draft-stream.ts` in the plugin repo) it forces a **mid-stream room rebind**: the stream object stores both `roomId` and `messageId`, and updates `roomId` after the first send returns the thread room id. Recovery and error-replace paths then have to read from the rebind, not the original inbound payload's room id.

Concretely, the plugin carries this complexity:
- `firstSend` callback on the draft-stream constructor — wired only when `shouldThread` is true
- a `roomId()` getter on the stream handle, polled by recovery/error-replace paths
- a branch in `monitor.ts` that constructs the stream differently for threading-on vs. threading-off cases
- a `client.replyInThread` wrapper used only on the first partial of a threaded reply

None of Sabha's peer chat platforms force this pattern on their clients:
- **Slack** threads use `thread_ts` — a parent-message reference, same channel id
- **Mattermost** threads use `root_id` — same shape, same channel
- **Discord** threads have discrete ids known up front from the inbound event or a synchronous `thread-create` call

The Sabha plugin is the only one with a mid-stream rebind. The data-model reason (threads-as-rooms) is well-justified for product features Slack doesn't have (per-thread membership, per-thread unread, "everything"-level involvement). But the **API surface doesn't have to expose the room change** at every mutation site.

## What

Add three id-only counterparts to the existing room-scoped mutating endpoints:

```
PATCH  /api/bots/messages/:id
DELETE /api/bots/messages/:id
POST   /api/bots/messages/:message_id/boosts
DELETE /api/bots/messages/:message_id/boosts/:id
```

(The `:message_id` param on the boosts routes follows from standard Rails nesting — see Implementation Unit 1.)

Behavior:
- **`PATCH /api/bots/messages/:id`** — same body as the existing room-scoped update; resolves the room via `Message#room`, authorizes against the bot's room access via `Current.user.rooms.exists?(id: message.room_id)`, then enforces ownership (`message.creator_id == Current.user.id`) the same way `set_own_message` does today. Returns the same JSON shape (`{ id, body: { html, plain } }`).
- **`DELETE /api/bots/messages/:id`** — same as above but calls `deactivate` + `broadcast_remove` + `notify_bots(:deleted)`.
- **`POST /api/bots/messages/:message_id/boosts`** — looks up the message by id, authorizes via room access (no ownership check — boosts can come from any participant), then runs the existing create flow.
- **`DELETE /api/bots/messages/:message_id/boosts/:id`** — analogous; ownership is the boost's `booster_id == Current.user.id` (already enforced by the existing controller's `where(booster: Current.user).find(...)`).

**`POST /api/bots/messages/:id` is intentionally not added.** Creation always happens in a specific room or via the existing `/thread` endpoint; there's no ambiguity to resolve.

**`GET /api/bots/messages/:id` is intentionally not added in this plan.** The streaming-rebind motivation only covers mutation. A read-shape addition can be a separate plan if a client need shows up.

The existing room-scoped endpoints stay forever as a permanent alias. No deprecation, no migration window — this is purely additive.

## Non-goals

- **No data-model change.** `Rooms::Thread` STI, `parent_message_id` on rooms, `Inbox::ThreadsQuery`, per-thread `memberships`, thread-aware push and broadcast — all unchanged. The data model change a Slack-style flatten would need is out of scope (see investigation in this repo's adjacent context for the 7+ feature dependencies).
- **No change to `POST /rooms/:room_id/messages/:message_id/thread`.** Existing bots that use it still work. They can keep working.
- **No deprecation of room-scoped mutating endpoints.** Both shapes coexist.
- **No new auth model.** Ownership and room-access checks reuse existing predicates.
- **No new wire shape for responses.** Same JSON, same headers (the `Location` header on create is already room-scoped via `room_message_url`; this plan doesn't touch create).

## Background

### Current request-path shape

`API::Bots::MessagesController` is mounted under `namespace :bots, do resources :rooms do resources :messages, ...`. The room is resolved in a `before_action :set_room` from `Current.user.rooms.find(params[:room_id])`. `set_own_message` then resolves the message *inside that room* and enforces `creator_id == Current.user.id`.

`API::Bots::Messages::BoostsController` follows the same shape, with `set_room_and_message` doing the two-step lookup.

The id-only counterparts invert one half of that lookup: load the message first, then check `Current.user.rooms.exists?(id: message.room_id)`. Same result, fewer URL parameters required.

### Why id-only is safe

Three properties of the existing schema make this trivially safe:

1. **`messages.id` is unique within a tenant.** Sabha runs on SQLite. In single-tenant mode there's one DB; in SaaS mode each workspace has its own SQLite DB (`storage/{env}/workspaces/{tenant_id}/main.sqlite3`) and `activerecord-tenanted` scopes every query to the active tenant. Ids can collide *across* tenants, but the access check runs entirely within the current tenant — `Message.active.find(:id)` and `Current.user.rooms.exists?(...)` both go through the tenant-scoped connection. No cross-tenant leak surface.
2. **Bot access is room-scoped at the membership layer.** `Current.user.rooms` (where `Current.user` is the bot) is `-> { active }`-scoped via the `User has_many :rooms, through: :memberships` association — inactive memberships are excluded the same way `set_room` already excludes them today. The `exists?(id: message.room_id)` check inherits that active scope, so the authorization outcome matches the existing path one-for-one.
3. **No new exposure surface.** A bot can already resolve any thread-room id by walking the inbound webhook payload (`message.thread = { id, parent_message_id }`) or by reading the response of `POST /thread`. Id-only ops don't expose anything a bot couldn't already reach.

### Why streaming flows benefit specifically

The Sabha plugin's draft-stream pattern (also used by Slack/Discord/Mattermost plugins via OpenClaw's `createFinalizableDraftLifecycle`) works like this:
1. agent yields partial text
2. plugin sends the first partial as a new message → captures `messageId`
3. agent yields more partials → plugin PATCHes the same `messageId` ~every 500ms / 100 chars
4. on completion, one final PATCH with the full text
5. on errors, plugin DELETEs the message and posts a fresh error message in its place

In Slack/Mattermost/Discord, step 1 returns a `messageId` and the channel id is the same as where the inbound event came from. Steps 3–5 reuse both. In Sabha today, step 1 *might* be a thread create that returns a brand-new room id; steps 3–5 must use the new room. The plugin currently solves this with a `firstSend` callback and a stream-internal `roomId` rebind. With id-only PATCH/DELETE, the plugin stores `messageId` only and the rebind disappears.

## Implementation units

### 1. Add the routes

File: `config/routes.rb`

Inside `namespace :bots do` (around line 162-180), after the existing `resources :rooms do ... end` block and before `resources :direct_messages`:

```ruby
resources :messages, only: %i[ update destroy ], controller: "messages_by_id" do
  resources :boosts, only: %i[ create destroy ], controller: "messages_by_id/boosts"
end
```

Standard Rails nesting; no `member do ... end` block needed. The boost route's parent param is `:message_id` automatically (consistent with the room-scoped boosts route's existing param name).

Final controller naming is bikesheddable — `MessagesByIdController` is one option to make the lookup-mode explicit; an alternative is to add the id-only actions to the existing `MessagesController` with separate routes that skip `set_room`. Either works; pick whichever fits the controller-organization convention better. Test plan below assumes the dedicated controller.

### 2. Add the controller

File: `app/controllers/api/bots/messages_by_id_controller.rb`

Mirrors `API::Bots::MessagesController` for `update` and `destroy`. Skips `set_room`. New `before_action :set_message_with_access_check` resolves the message via a single AR query that combines existence and access:

```ruby
def set_message_with_access_check
  @message = Message.active
                    .where(room_id: Current.user.rooms.select(:id))
                    .find(params[:id])
  @room = @message.room
end
```

This single-query form is deliberate: an inaccessible message id and a nonexistent message id both raise `ActiveRecord::RecordNotFound`, which `API::Bots::BaseController#rescue_from ActiveRecord::RecordNotFound` (`app/controllers/api/bots/base_controller.rb:7-20`) turns into the canonical JSON 404 envelope `{ error: "Not found", code: "not_found" }`. **Do not use `head :not_found`** — it would produce an empty-body 404, which contradicts the existing bot-API 404 contract on every other endpoint.

Note the choice of `:not_found` (not `:forbidden`) for the no-room-access case. Today's `set_room` produces the same `RecordNotFound` from `Current.user.rooms.find(...)` — same JSON envelope, same status. The id-only variant matches one-for-one. Don't leak existence of messages in rooms the bot can't see.

The `Current.user.rooms` association on `User` is `-> { active }`-scoped via `:memberships` (see point 2 of "Why id-only is safe"), so this query inherits the active-membership filter automatically.

The `set_own_message` ownership check on `update` / `destroy` stays:

```ruby
before_action :enforce_ownership, only: %i[update destroy]

def enforce_ownership
  head :forbidden unless @message.creator_id == Current.user.id
end
```

`update` / `destroy` action bodies are copy-paste of the existing controller's actions, with `@room` already populated by the `before_action`.

### 3. Add the boosts controller

File: `app/controllers/api/bots/messages_by_id/boosts_controller.rb`

Same shape as `API::Bots::Messages::BoostsController` but with `set_room_and_message` replaced by the same single-query form used by the message controller:

```ruby
def set_room_and_message
  @message = Message.active
                    .where(room_id: Current.user.rooms.select(:id))
                    .find(params[:message_id])
  @room = @message.room
end
```

Same JSON 404 envelope guarantee as the message controller above (no `head :not_found`).

`create` and `destroy` action bodies are unchanged.

### 4. Tests

Files:
- `test/controllers/api/bots/messages_by_id_controller_test.rb`
- `test/controllers/api/bots/messages_by_id/boosts_controller_test.rb`

Scenarios for the message controller:
- `PATCH /api/bots/messages/:id` succeeds for the bot's own message in a room the bot has access to
- `PATCH /api/bots/messages/:id` returns 403 for a message owned by another user
- `PATCH /api/bots/messages/:id` returns 404 with the canonical JSON envelope `{ error: "Not found", code: "not_found" }` for a message in a room the bot has no access to (regression: assert body, not just status, so the existing `rescue_from` contract isn't accidentally bypassed by a future refactor)
- `PATCH /api/bots/messages/:id` returns 404 with the same canonical JSON envelope for a nonexistent message id (proves the access-denied and not-found paths are indistinguishable to clients)
- `PATCH /api/bots/messages/:id` succeeds for a message in a thread the bot can see (regression test — proves the id-only path resolves into thread rooms correctly without the caller passing the thread room id)
- `PATCH /api/bots/messages/:id` returns 404 (with JSON envelope) for a soft-deleted message (`active: false`)
- `DELETE /api/bots/messages/:id` deactivates the message and broadcasts removal
- `DELETE /api/bots/messages/:id` returns 403 for a message owned by another user
- the response shape and broadcast surface match the room-scoped endpoint (regression: `notify_bots` fires, `broadcast_update` / `broadcast_remove` fire, the room's `messages_count` counter behaves the same)

Scenarios for the boosts controller:
- `POST /api/bots/messages/:message_id/boosts` creates a boost for any message the bot can see (no ownership check)
- `POST /api/bots/messages/:message_id/boosts` returns 404 with the canonical JSON envelope for a message the bot can't reach (assert body, not just status)
- `DELETE /api/bots/messages/:message_id/boosts/:id` removes the bot's own boost
- `DELETE /api/bots/messages/:message_id/boosts/:id` returns 404 with the canonical JSON envelope for someone else's boost (the existing `where(booster: Current.user).find(...)` produces this)

A shared test scenario worth its own file:
- thread message round-trip: `POST /rooms/:room_id/messages/:message_id/thread` returns `{ thread: { id, parent_message_id }, message: { id } }`; the test then PATCHes the message via `/api/bots/messages/:id` (passing `response["message"]["id"]`, never reading `response["thread"]["id"]`), and asserts the body update lands. This is the regression that the rebind elimination depends on.

### 5. Documentation

File: `docs/plans/ID-ONLY-BOT-MESSAGE-OPS-PLAN.md` (this doc — moves to a "shipped" status when merged).

Updates to `docs/features/BOT_INTEGRATION.md`:

1. **Endpoints table (around lines 70–78):** add the id-only entries:
   - `Edit own message (id-only)` — `PATCH /messages/{id}`
   - `Delete own message (id-only)` — `DELETE /messages/{id}`
   - `Add reaction (id-only)` — `POST /messages/{message_id}/boosts`
   - `Remove reaction (id-only)` — `DELETE /messages/{message_id}/boosts/{id}`
2. **Curl examples block (around lines 232–265):** add inline examples for each id-only verb.
3. **URL-discovery contract (lines 64–66):** revise the "server is the source of truth" paragraph to carve out id-only paths. Recommended replacement text:

   > Per-room URLs (e.g. `messages_url`) are server-provided in webhook and registration payloads — clients should consume them directly because they may include tenant prefixes, signed query params, or version markers tied to a specific room. **Id-only message URLs** (`/api/bots/messages/:id`, `/api/bots/messages/:id/boosts/...`) are derived from `api_base_url` because they're stable across rooms and tenants and there's no per-room context to encode. Both shapes are part of the bot-API contract; the asymmetry is intentional.

   This revision is the cheap fix for the id-only/discovery-story tension noted in Risks → "URL discovery contract revision." Adding `message_url` to message envelopes (the alternative) is deferred indefinitely; revisit only if URL derivation becomes costly for some future reason.

If `/skill` (the LLM-readable bot API reference) is generated from a single source, update that source too.

## Backward compatibility

Strictly additive. No headers, no params, no response shapes change on existing endpoints. Existing bots keep working. No version bump needed in the bot API contract.

## Risks

### Existence-leak via 404 vs. 403

The id-only routes return `:not_found` for both "message doesn't exist" and "bot can't access this message's room." That's the same disambiguation the room-scoped routes already produce (a `Current.user.rooms.find(other_room_id)` is a 404, not a 403). No new leak surface, but worth verifying the test plan covers the "bot in room A tries to edit message in room B" case and confirms both rooms' message ids return 404.

Mitigation: tests above cover this explicitly.

### Performance: the bot's room set could be large

The single-query access check `Message.active.where(room_id: Current.user.rooms.select(:id)).find(:id)` becomes a SQL subquery over the `memberships` join. For a bot in a few hundred rooms this is microseconds. For a bot in tens of thousands of rooms this is still microseconds (the planner converts the `IN (subquery)` into a join with index probes, not a scan). No realistic risk; flagging only because the existing room-scoped path goes through `Current.user.rooms.find(room_id)` first and then `@room.messages.active.find(message_id)` — two probes; the id-only path is one.

Mitigation: none needed unless benchmarks surprise.

### Audit trail clarity

Today's logs and per-room metrics show "bot X edited message Y in room Z" via the route. Id-only routes elide the room in the URL. If logs grep for `room_id=...` to attribute mutations, that pattern breaks.

Mitigation: ensure `@room` is populated in the controller (it is, after the access check) so anything downstream that reads `@room` for logging or notification still works. Per-room metric counters scoped on the controller-level instrumentation should explicitly read from `@message.room_id` rather than `params[:room_id]`.

### Test maintenance: two parallel controllers

Two controllers + two test files cover what was one. If the request body schema or notification side effects change in the room-scoped path, the id-only path needs the same change.

Mitigation: extract the action bodies into a shared concern (e.g., `BotMessageMutations`) once both controllers exist and have green tests. Don't pre-extract — start with the duplication, refactor when the test surface confirms behavioral parity.

### URL discovery contract revision

`docs/features/BOT_INTEGRATION.md:64-66` currently tells clients to consume server-provided URLs (e.g. `messages_url` on each room object) instead of deriving paths from `api_base_url + room_id`. The id-only routes have **no** equivalent server-provided URL — clients must derive `/api/bots/messages/:id` from `api_base_url`. That partially contradicts the existing guidance.

Two options:

1. **Add `message_url` to message envelopes** in webhook payloads, the room/messages list, and other surfaces. Preserves the discovery contract uniformly. Cost: jbuilder additions across several views, plus a new url helper.
2. **Revise the doc contract** to acknowledge that id-only paths are derived from `api_base_url`, and only per-room URLs go through the discovery channel.

Since the Sabha plugin is the only current client and isn't in production, option 2 is the right cost-vs-value trade. Add to Implementation Unit 5 (Documentation) a one-paragraph revision in `BOT_INTEGRATION.md:64-66` along the lines of:

> Per-room URLs (e.g. `messages_url`) are server-provided in webhook and registration payloads — clients should consume them directly. Id-only message URLs (`/api/bots/messages/:id`, `/api/bots/messages/:id/boosts/...`) are derived from `api_base_url` because they're stable across rooms and tenants. Both shapes are part of the bot-API contract.

If a future Sabha bot ecosystem makes derivation costly (e.g. URL versioning, subdomain split), option 1 is still available — `message_url` can be added to message envelopes additively without breaking either contract.

## Open question (resolved)

**Boosts URL shape.** The cleaner route block in Implementation Unit 1 (`resources :messages do resources :boosts end`, no `member do` overrides) naturally produces `:message_id` for the boost route's parent param. This matches the existing room-scoped boosts route exactly (`/api/bots/rooms/:room_id/messages/:message_id/boosts`), which is the right consistency to preserve.

## Migration path for the Sabha plugin

The Sabha plugin (`@sabha-co/openclaw-sabha`) is the only current bot-API consumer and is not yet in production. **Clean break: replace the room-scoped methods with id-only ones outright.** No transition window, no dual-path tests, no version sniffing — server PR ships, plugin PR ships against it, done.

After server ships:

1. **Replace** `client.editMessage(roomId, messageId, text)` and `client.unsendMessage(roomId, messageId)` with `client.editMessage(messageId, text)` and `client.unsendMessage(messageId)` in `src/client.ts`. Method names stay the same; signatures shrink. Old method bodies deleted, not deprecated.
2. **Replace** `client.listReactions(roomId, messageId)` and the boost-related calls with their id-only counterparts.
3. Update the draft-stream loop in `src/draft-stream.ts`: the `roomId` field on the stream state becomes vestigial for editing. Trim it (or leave it for read-history / fresh-error-message paths if those still need it).
4. Trim `firstSend`'s return shape from `{ roomId, messageId }` to `{ messageId }`. The `monitor.ts` deliver-path branch that wires `firstSend` only on `shouldThread === true` keeps the threading-on guard but no longer needs to capture `r.thread.id` from the response.
5. Update `docs/CHANNEL-PLUGIN-COMPARISON.md`: the "Sabha is the only plugin with a mid-stream rebind" framing in section 7 (streaming agent replies) becomes a historical note. Sabha now matches the Slack/Mattermost shape at the API level even though the data model still uses thread rooms server-side.

The plugin-side PR ships after the server PR merges and a Sabha release cuts. Pin the plugin's `peerDependencies` (or its installation/setup-wizard `probeBaseUrl` check) against the new server version if version skew is a concern; otherwise rely on the lockstep release to keep them in sync.

## Exit criteria

- `PATCH /api/bots/messages/:id`, `DELETE /api/bots/messages/:id`, `POST /api/bots/messages/:message_id/boosts`, `DELETE /api/bots/messages/:message_id/boosts/:id` are all wired, passing tests, and behaviorally equivalent to their room-scoped counterparts on the same message
- the existing room-scoped routes continue to pass their existing tests (no regression)
- the bot-API reference doc lists both shapes
- the Sabha plugin's draft-stream loop can be migrated to id-only PATCH/DELETE without changing its public surface (verified by writing a follow-up PR in the plugin repo, even if not merged immediately)

---

# Phase 2 (conditional) — inline thread-reply on POST

**Decide whether to build this only after Phase 1 ships and clients have used it for some time.** Phase 1 alone eliminates the rebind. Phase 2 doesn't help streaming clients further — it's an ergonomic shortcut for any client that wants to start a thread reply in a single round trip.

## Why

After Phase 1 ships, the streaming flow looks like:

1. `POST /api/bots/rooms/:parent_room_id/messages/:parent_message_id/thread` with first partial → returns `{ thread: { id }, message: { id: M1 } }`
2. `PATCH /api/bots/messages/M1` for each subsequent partial
3. Final `PATCH /api/bots/messages/M1` with the full text

The rebind is gone. But step 1 is still a thread-specific endpoint with a different request shape than the regular send. Clients have to special-case threading in their send path. Specifically:

- the Sabha plugin's `client.replyInThread(roomId, messageId, text)` exists *only* to call this endpoint
- the deliver path in `monitor.ts` still has a `shouldThread === true` branch that wires `firstSend` callback exclusively for the thread-creation flow
- the SDK's `createFinalizableDraftLifecycle` in OpenClaw treats the first send as a normal `sendMessage` for Slack/Mattermost/Discord; Sabha is the odd one out because of the dedicated `replyInThread` call

The peer-shape simplification: in Slack and Mattermost, the first send to a thread is just a normal post with a parent reference (`thread_ts` or `root_id`). The plugin doesn't have a "thread-creation send" code path at all.

To get to the same shape on Sabha **without changing the data model**, accept a `parent_message_id` parameter on the regular `POST /api/bots/rooms/:room_id/messages` and have the server route the message into the thread room transparently.

### Won't this just hide the same complexity in the server?

Mostly yes, and that's fine. The thread-create code path already exists (`Rooms::Thread.find_or_create_for`, idempotent via the `parent_message_id` unique index). The work moves from "client makes two API calls" to "server resolves at one endpoint." Net code: smaller (the client side simplifies more than the server side grows).

### When *not* to build Phase 2

- Phase 1 turns out to be sufficient — clients are happy, no one complains about the two-step thread flow
- The plugin's `replyInThread` and `firstSend` complexity stays acceptable after Phase 1 trims the rebind
- Other Sabha bot-API consumers exist that depend on the current `/thread` endpoint's response shape (`{ thread, message }`) and we'd rather not split semantics

If those conditions hold, the existing `/thread` endpoint stays as the canonical thread-create surface and Phase 2 doesn't ship.

### When to build Phase 2

- Multiple bots (or multiple plugins) duplicate the "if threading then `/thread` else regular send" branching, indicating the asymmetry is friction across the ecosystem
- Plugin maintainers ask for it explicitly
- Sabha gets a richer set of message verbs (file uploads in threads, scheduled thread sends, etc.) and it becomes painful to keep two parallel endpoint families

## What

Augment the existing `POST /api/bots/rooms/:room_id/messages` to accept an optional `parent_message_id` request parameter. When present, the server:

1. Looks up the parent message scoped to the URL room (`@room.messages.active.find(parent_message_id)`); 404 if not found in this room
2. Validates that the parent is itself a top-level message — not already inside a thread room (Sabha doesn't support nested threads); 422 otherwise
3. Calls `Rooms::Thread.find_or_create_for(parent_message, users: @room.users)` to get or create the thread room
4. Creates the message in the resolved thread room (not the URL room)
5. Returns `201 Created` with `Location: room_message_url(thread_room, message)` *and* a JSON body `{ id, room_id }` so the caller has the resolved room id without re-parsing the Location header

The Location header alone is the canonical reference today. Returning a JSON body alongside it is additive — existing clients that read only the Location keep working; clients that want the room id without parsing URLs read the body.

When `parent_message_id` is absent the endpoint behavior is unchanged (no body, just Location). This matters: existing bots see no behavior change.

**Transport: query string, not JSON body.** The existing `POST /messages` endpoint reads `request.body` as raw text (the message body itself; see `messages_controller.rb:84-87`'s `reading(request.body) { ... }` block) rather than parsing it as JSON. So `parent_message_id` is passed as a query parameter:

```
POST /api/bots/rooms/42/messages?parent_message_id=99
Content-Type: text/plain

Hello, this is the message body
```

For multipart requests with `attachment`, `parent_message_id` is included as form data alongside the attachment field. Either way, it's read via `params[:parent_message_id]`, never from the raw body. Don't add a JSON-body branch — the existing endpoint's text-body contract is preserved.

## Non-goals (Phase 2)

- **No removal of `POST /rooms/:room_id/messages/:message_id/thread`.** The dedicated thread-create endpoint stays as a permanent alias. Existing bots keep working.
- **No support for `parent_message_id` pointing at a message in a different room than `:room_id`.** The parent must be in the URL room; cross-room thread creation isn't a use case.
- **No nested thread support.** A `parent_message_id` that points at a message already in a thread room returns 422. (Phase 1 doesn't change this either; Sabha's data model has never supported nested threads.)
- **No new attachment semantics.** If both `attachment` and `parent_message_id` are present, the message is created in the thread room with the attachment. No special handling.

## Implementation outline (Phase 2)

Smaller than Phase 1. Roughly:

### 1. Augment the create action

File: `app/controllers/api/bots/messages_controller.rb`

Replace the `create` action's straight-line flow with:

```ruby
def create
  target_room = resolve_target_room
  return if performed?  # resolve_target_room may render :unprocessable_entity for nested-thread input

  @message = target_room.messages.create_with_attachment(message_params)

  if @message.persisted?
    @message.broadcast_create
    @message.broadcast_mentionee_sidebar_updates
    notify_bots(@message, :created)

    if params[:parent_message_id].present?
      render json: { id: @message.id, room_id: target_room.id },
             status: :created,
             location: room_message_url(target_room, @message)
    else
      head :created, location: room_message_url(target_room, @message)
    end
  else
    render json: { error: @message.errors.full_messages.to_sentence, code: "validation_failed" }, status: :unprocessable_entity
  end
rescue LoadError
  render json: { error: "Storage service unavailable", code: "service_unavailable" }, status: :service_unavailable
end

private
  def resolve_target_room
    parent_message_id = params[:parent_message_id]
    return @room if parent_message_id.blank?

    parent = @room.messages.active.find(parent_message_id)
    if parent.room.thread?
      render json: { error: "parent_message_id cannot point at a message inside an existing thread", code: "validation_failed" },
             status: :unprocessable_entity
      return nil
    end

    Rooms::Thread.find_or_create_for(parent, users: @room.users)
  end
```

**Decision: 422 for nested-thread input.** A nested-thread `parent_message_id` is a well-formed request that's semantically invalid, so 422 (unprocessable entity) is correct over 400 (bad request). The implementation uses `render` + `return nil` rather than `raise ActionController::BadRequest` so the status code matches the spec and tests in this plan exactly — no controller-level rescue handler needed.

**Decision: response body only when `parent_message_id` is present.** The pre-Phase-2 behavior of `POST /messages` is `head :created` with no body. To stay strictly non-breaking, callers that don't opt into `parent_message_id` continue to get the empty-body response; only callers that pass `parent_message_id` get the new `{ id, room_id }` body. Slightly asymmetric, but eliminates contract-test risk and matches the rule "callers that opt into a new feature see new behavior; everyone else is untouched." (The `/thread` endpoint already returns a body of its own shape; this is consistent.)

**Note on attachments + `parent_message_id`.** `message_params` reads from a permit list that depends on whether `params[:attachment]` is present (`messages_controller.rb:84`). `parent_message_id` is **not** part of `message_params`; it's read directly from `params[:parent_message_id]` in `resolve_target_room`. This means `parent_message_id` works alongside `attachment` without any change to the permit logic. A future maintainer should not try to fold `parent_message_id` into `message_params` — it's a routing-level concern (which room to land in), not a message attribute.

### 2. Tests

Files:
- `test/controllers/api/bots/messages_controller_test.rb` — extend with new scenarios

Scenarios:
- `POST /rooms/:room_id/messages` with `parent_message_id` creates the message in a (possibly newly-created) thread room
- the response `Location` points to the thread room's message URL, not the URL room's
- the response body contains `{ id, room_id }` where `room_id == thread_room.id`
- repeating the same `POST` with the same `parent_message_id` (idempotent thread-create) creates a second message in the same existing thread room
- `parent_message_id` pointing at a message in another room returns 404 (the URL room scope of `@room.messages.active.find` enforces this)
- `parent_message_id` pointing at a soft-deleted message returns 404 (`active` scope)
- `parent_message_id` pointing at a message already in a thread room returns 422
- `POST /rooms/:room_id/messages` without `parent_message_id` keeps existing behavior: `head :created` with the Location header, no body (regression-pinned, since the Phase 2 implementation is body-only-when-opted-in)
- thread-creation side effects fire: `notify_bots` for the message, plus `update_thread_reply_count` and `update_parent_message_threads` Turbo Stream broadcasts to the parent room

### 3. Documentation

File: `docs/features/BOT_INTEGRATION.md`

- Add `parent_message_id` to the `POST /messages` parameter table, marked explicitly as a query-string parameter (not JSON body)
- Add a curl example showing inline thread-reply with the param in the URL:

  ```sh
  curl -X POST "https://sabha.example/api/bots/rooms/42/messages?parent_message_id=99" \
       -H "Authorization: Bearer $BOT_KEY" \
       -H "Content-Type: text/plain" \
       --data "Reply body in the new thread"
  ```

- Mark the dedicated `POST /thread` endpoint as "still supported, equivalent to POST /messages with `parent_message_id`"

## Backward compatibility

Strictly additive:
- new optional param: no existing client sends it
- response body unchanged for callers that don't pass `parent_message_id` (still `head :created` with the existing Location header); body-only-when-opted-in is the committed shape per Implementation Unit 1

`POST /thread` continues to work; both endpoints route through the same `Rooms::Thread.find_or_create_for` factory, so they're guaranteed to land messages in the same thread room for the same `parent_message_id`.

## Risks (Phase 2)

### Test coverage drift between `/thread` and `POST /messages` with `parent_message_id`

Two endpoints route through the same factory but have separate test suites. If thread-creation semantics change (e.g., a new param to `find_or_create_for`), both tests need to update.

Mitigation: shared test helper that exercises the thread-creation path under both routes.

### Pre-existing race in `Rooms::Thread.find_or_create_for` (not introduced by this plan; flagged for awareness)

`Rooms::Thread.find_or_create_for` (`app/models/rooms/thread.rb:36-39`) is `find_by ||  create_for` with no `RecordNotUnique` rescue. Two bots posting concurrently to the same parent message can race: both pass the `find_by` check (finds nothing), both try to create, the partial unique index on `parent_message_id` lets exactly one INSERT succeed, the other gets a 500. The data integrity is sound (only one thread room per parent ever exists); the failure mode is a 5xx for the loser.

Phase 1 doesn't change this. Phase 2 inherits it. Both phases are equally exposed.

Mitigation (out of scope for this plan): add `rescue ActiveRecord::RecordNotUnique; find_by(parent_message: parent_message)` to `find_or_create_for`. Worth doing as a separate small PR; not a Phase 2 prerequisite, but the idempotency claim ("idempotent thread-create") in the test scenarios above only holds *up to concurrency*, not under it. Note this in the test docstring.

### Discovery: bots may not realize `parent_message_id` exists

A new optional param is easy to miss in docs. Bots keep using the legacy two-step flow indefinitely.

Mitigation: explicitly document Phase 2 as the preferred shape in `BOT_INTEGRATION.md` and update the `/skill` LLM-readable bot-API reference if it exists. Keep Phase 1's id-only ops as the doc-blessed mutation path so the simplification is end-to-end.

## Migration path for the Sabha plugin (Phase 2)

After Phase 2 ships:

1. Replace `client.replyInThread(roomId, messageId, text)` with a unified `client.sendMessage(roomId, text, { parentMessageId? })`. The legacy method either becomes a thin wrapper around `sendMessage` or is deleted.
2. The deliver path in `monitor.ts` no longer has a `shouldThread === true` branch wiring `firstSend` exclusively for thread-create. The first send is just `client.sendMessage(parentRoomId, partial, { parentMessageId: payload.message.id })` for the threading-on case.
3. `firstSend` callback may be deletable entirely if the draft-stream loop can read the `room_id` from the response body of the first send. Verify against the SDK's `createFinalizableDraftLifecycle` shape — the loop already captures `messageId` from the first response; capturing `room_id` alongside is a small addition.
4. `CHANNEL-PLUGIN-COMPARISON.md` updates: the "Sabha is the only plugin with a `firstSend` rebind" framing is now obsolete in two senses (Phase 1 killed the rebind; Phase 2 killed the dedicated thread-creation send code path).

The plugin-side PR for Phase 2 is independent of Phase 1's plugin migration and can land later.

## Exit criteria (Phase 2)

- `POST /api/bots/rooms/:room_id/messages` accepts `parent_message_id` and routes the resulting message into the resolved thread room
- the response includes the resolved `room_id` so callers don't have to parse the Location header
- the existing `POST /rooms/:room_id/messages/:message_id/thread` endpoint continues to pass its tests (no regression)
- both endpoints land messages in the same thread room for the same `parent_message_id` (verified by a shared test helper)
- the bot-API reference doc lists `parent_message_id` as the preferred shape and points at `/thread` as the legacy alias
- the Sabha plugin can collapse `client.replyInThread` into the unified `client.sendMessage` path (verified in the same way as Phase 1's plugin-migration check)

## Decision criterion — when to revisit

Revisit Phase 2 once Phase 1 has been in production for **at least one Sabha plugin release cycle** (so the rebind elimination has been used in real streaming flows). Decision input:

- has any plugin or bot maintainer asked for inline thread-reply?
- after the Phase 1 plugin migration, how much code does the `firstSend` + `replyInThread` surface still occupy? If it's already trivial, Phase 2 is paint over a non-pain-point.
- does Sabha have new bot-API consumers that would benefit from the unified shape?

If two of three lean toward "yes," ship Phase 2. Otherwise, mark Phase 2 as "deferred indefinitely; revisit on demand" and leave this section as the design record.

---

## References

- `app/controllers/api/bots/messages_controller.rb` — current room-scoped controller
- `app/controllers/api/bots/messages/boosts_controller.rb` — current room-scoped boosts controller
- `app/controllers/api/bots/messages/threads_controller.rb` — thread create endpoint (unchanged by this plan)
- `app/models/room.rb`, `app/models/rooms/thread.rb` — STI thread model (unchanged by this plan)
- `app/models/message.rb` — `room_id` foreign key (the only association the access check relies on)
- `config/routes.rb` — bot namespace routes
