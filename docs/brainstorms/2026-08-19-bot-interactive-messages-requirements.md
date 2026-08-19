---
title: "Interactive bot messages — host-rendered actions that round-trip to the bot"
date: 2026-08-19
topic: bot-interactive-messages
---

# Interactive bot messages — host-rendered actions that round-trip to the bot

## Summary

Give bots a way to put **interactive controls** on a message — at minimum, buttons — that
Sabha renders natively and whose clicks round-trip back to the authoring bot. Bots send a
constrained **declarative document** (JSON, never markup or script); Sabha owns rendering
server-side; a member's click dispatches an event to the bot over the existing signed
webhook / WebSocket channel; the bot responds by **editing its own message** through the
existing bot message-update API, and the edit re-renders and broadcasts to the room like any
other update.

v1 is deliberately narrow: **in-message controls that update the shared message.** No
ephemeral ("only you can see this") responses, no modals, no input fields, no per-user
selection state held by Sabha. Those are called out under scope boundaries.

This document started life as a plan (2026-08-12) that had already committed to a Block Kit
subset. It has been pulled back to a brainstorm because upstream prior art landed in the
meantime — once-campfire discussion #244 and PR #247 — and it argues, credibly, for a much
smaller primitive. The **shape of the document** is now the central open decision (see
Outstanding Questions), and the plan will be re-derived from whichever shape is chosen.

---

## Problem Frame

Sabha already has a mature bot layer: bots are `User`s with `role: :bot`, they post and edit
messages through `/api/bots/*`, and Sabha dispatches HMAC-signed events out to them
(`Webhook` + `User::Bot::WebhookSigner` + `Bot::EventPayload`, fanned out from
`notify_bots`; WS-connected bots get the same events over `BotEventsChannel`). What bots
cannot do today is present **interactivity**: everything a bot sends is inert ActionText.
`/skills` says so explicitly — *"No apps / slash commands / Block Kit (unlike Slack)."*

A bot message is therefore a dead end. The workarounds are all bad, and #244 names them well:

- **Outbound links** — a GET that mutates state is a loaded gun in chat: unfurlers,
  prefetchers and link scanners fire it with no human involved, and the safe version needs an
  interstitial confirm page. Links also punt the member into a browser tab for a one-tap
  "yes, deploy it."
- **Typed replies** — need a command vocabulary the member must remember, error-prone on a
  phone, and un-disambiguable when three prompts are outstanding.
- **Boosts** — a reaction, not a decision; no way to express "these three specific options."

The natural fix is a declarative, host-rendered UI contract — which is the paradigm Sabha
already runs on. Hotwire renders HTML on the server and swaps it into the client; a bot
describing UI as data and handing rendering to the host is the same bet. It:

- **Keeps the security boundary clean.** Bots emit a whitelisted schema, never markup or
  script. Rendering stays under Sabha's control (DOM, CSS tokens, sanitization).
- **Reuses the hard half.** Outbound signed dispatch, SSRF protection, async delivery with
  retries, WS fan-out, and the bot message-update endpoint all exist. What is new is a
  document, a renderer, and one **inbound** interaction endpoint.
- **Is agent-native.** LLM agents increasingly need a human in the loop, and
  `[ Run it ] [ Show me the diff ] [ No ]` is a far better consent surface than "type yes."

The aesthetic risk is real: Block Kit is Sabha's design anti-reference (Discord / SaaS widget
overload). Whatever shape is chosen, the mitigation is scope — a tight, opinionated set of
controls styled with Sabha's own tokens so bot UI reads as native.

---

## Key Decisions

- KD1. **Declarative document, host-rendered, fail-closed.** Bots send data; Sabha renders it
  server-side from a whitelist of control types. Unknown types or malformed shapes are
  rejected at write time (`422` naming the offending field/path), never silently dropped and
  never rendered raw. The document is never shipped to the client to be turned into DOM in
  JS.

- KD2. **The document lives on the message.** A JSON column on `messages`, no sibling table.
  The message stays the single unit of rendering, caching, and broadcast — the fragment cache
  already keys on the message, so a document update busts it and re-broadcasts for free.
  Portable `json` column per the dual-engine rule.

- KD3. **Bots-only authoring in v1.** A non-bot creator supplying a document is rejected. A
  signed-in member can reach bot-ish endpoints in some setups; letting anyone attach buttons
  would hand every member a way to post UI that impersonates a bot.

- KD4. **The round-trip is: click → event to the authoring bot → bot edits its message.**
  Sabha does not interpret the click beyond validating and forwarding it. The response spine
  is the existing bot message-update API, extended to accept the document. A synchronous
  inline reply (the bot's HTTP 200 body carries a new document, mirroring
  `Webhook#deliver_with_reply`) is a possible fast-follow, not v1.

- KD5. **Sabha holds no per-user interaction state.** Updates hit the shared message; every
  member sees the result of one member's click. Selection state ("you voted ramen"),
  single-use, expiry and permissions are **bot concerns**, made practical by the edit
  endpoint. This is #244's position, and it is where #247 lost the plot (see Prior Art).

- KD6. **Interactions route to the authoring bot only.** A different bot cannot receive
  another bot's clicks. Dispatch reuses the existing signed webhook path or `BotEventsChannel`
  for WS-connected bots; no new signing, SSRF, or delivery machinery.

- KD7. **Interaction events are idempotent by construction.** Every dispatched interaction
  carries a stable event id; delivery retries keep the same id so a bot can dedup. This
  answers the double-click / retry question at the protocol level rather than only in the UI.

- KD8. **Action values are opaque and untrusted.** Sabha echoes them back verbatim and never
  interprets them; bots must sign or namespace values rather than trust them. Documented
  loudly. Sabha validates only that a clicked value **exists on the stored message** and is
  not disabled (forgery guard).

- KD9. **Progressive enhancement.** Controls are real form submissions that work without JS;
  Turbo/Stimulus enhance (in-place submit, optimistic pending state). Styled with existing
  tokens — no bot-supplied colors, icons, or arbitrary appearance.

- KD10. **Both deployment modes from day one.** Self-hosted and SaaS: dispatch is
  out-of-process either way, the interaction endpoint is an ordinary tenanted controller, and
  the WS stream is already tenant-scoped.

---

## Actors

- A1. **Bot** — a `User` with `role: :bot`; authors the document, receives interaction events,
  edits its own message in response.
- A2. **Member** — a human who can view the room; clicks a control.
- A3. **Room** — every other member, who sees the shared message re-render after the bot's
  edit.
- A4. **Bot author / agent** — the human or LLM writing the bot; needs the schema and payload
  documented well enough to emit working UI with minimal Sabha-specific priming.
- A5. **Sabha** — validates, renders, authorizes, dispatches, re-broadcasts. Never executes
  bot-supplied markup, never holds interaction state.

---

## Requirements

**Document & authoring**

- R1. A message can optionally carry a document, persisted alongside its ActionText body. Human
  messages are unaffected and render exactly as today.
- R2. Only bots author documents in v1; a document on a non-bot message is rejected.
- R3. The document is validated fail-closed at write time against a whitelist of control types
  and shapes; invalid documents return `422` identifying the offending field. A `2xx` means the
  document was stored exactly as sent.
- R4. Control values (the opaque round-trip token) are unique within a message, capped in
  length, and opaque to Sabha.
- R5. The document is capped in size (control count) to keep messages readable and bound the
  render.
- R6. Text inside the document is routed through Sabha's existing content filters — no raw
  HTML — and any `mrkdwn`-like text is a documented, intentional divergence from Slack's
  dialect.

**Rendering**

- R7. Sabha renders the document server-side into native, token-styled controls beneath (or
  in place of) the message body; the message's fragment caching and broadcast pipeline are
  unchanged.
- R8. Controls are real form submissions and work without JS; Turbo/Stimulus enhance them.
- R9. A bot can **update, disable, or remove** controls through the existing bot
  message-update API; the edit re-renders and re-broadcasts to the room.
- R10. Push-notification and preview surfaces that cannot render controls degrade to the
  message body (no dead buttons in a notification).

**Interaction & dispatch**

- R11. Clicking a control creates an interaction only if the member can view the room and the
  clicked value exists on the stored message and is not disabled; anything else is rejected.
- R12. Interactions are rate-limited per member.
- R13. Each interaction dispatches one event to the **authoring bot only** — over the bot's
  webhook (signed, SSRF-guarded, async with retries) or `BotEventsChannel` if the bot is
  WS-connected — carrying the acting member, room, message, and the clicked value.
- R14. Every event carries a stable event id; retries reuse it.
- R15. A control that requires round-trip is rejected at write time if the bot has **no**
  delivery path (no webhook and not a WS-capable bot); removing a bot's webhook later
  disables its existing round-trip controls rather than 500ing on click.
- R16. The click is acknowledged immediately (accepted, not "done"); the UI may show a pending
  state until the bot's edit lands.
- R17. A bot triggering its own controls does not receive a callback.

**Modes & docs**

- R18. Works identically in self-hosted and SaaS modes.
- R19. `docs/features/BOT_INTEGRATION.md` and `/skills` document the schema, the event
  payload, and the update contract; the stale "No Block Kit" line is corrected.

---

## Key Flows

- F1. Post an interactive message
  - **Trigger:** A1 `POST`s a message with a document.
  - **Steps:** Sabha validates fail-closed → saves → renders the controls server-side →
    broadcasts to the room.
  - **Outcome:** every member sees native controls under the message.
  - **Covers:** R1–R8, R15.

- F2. Click → round-trip → edit
  - **Trigger:** A2 clicks a control.
  - **Steps:** Sabha authorizes A2, checks the value against the stored document, rate-limits,
    dispatches an event (with id) to A1, acks the click; A1 receives the event, decides, and
    `PATCH`es its message with a new body/document; Sabha validates, re-renders, re-broadcasts.
  - **Outcome:** the whole room sees the updated message.
  - **Covers:** R9, R11–R14, R16.

- F3. Close it out
  - **Trigger:** A1 decides the prompt is finished (deadline, quorum, single-use consumed).
  - **Steps:** A1 `PATCH`es the message with controls disabled or removed and a body showing
    the result.
  - **Outcome:** no stale live buttons in the room.
  - **Covers:** R9.

- F4. Retry / double-click
  - **Trigger:** A2 double-clicks, or A1's endpoint times out on first delivery.
  - **Steps:** two interactions dispatch (or one dispatch retries) with ids A1 can dedup.
  - **Outcome:** exactly-once *effect* on A1's side, without Sabha holding state.
  - **Covers:** R14.

- F5. Forged or stale click
  - **Trigger:** a request names a value not on the message, or a disabled one, or comes from
    a non-member.
  - **Steps:** rejected before any dispatch.
  - **Covers:** R11.

---

## Acceptance Examples

- AE1. **Covers R2, R3.** Given a human posts via a bot-adjacent endpoint with a document: the
  message is rejected. Given a bot posts `{ ..., "unknown_control": {} }`: `422` naming the
  offending path; nothing stored.
- AE2. **Covers R11, R13, R17.** Given a bot message with controls `deploy` / `hold`: a member
  clicking `deploy` produces exactly one signed event to that bot with value `deploy`; a
  member clicking a value not on the message gets rejected with no dispatch; a bot clicking
  its own control produces no event.
- AE3. **Covers R9, R7.** Given the bot receives the event and `PATCH`es its message with the
  controls removed and body "Deployed by Ada": every member's view re-renders in place with
  no buttons.
- AE4. **Covers R14.** Given the bot's endpoint returns 503 on the first delivery: the retry
  carries the same event id.
- AE5. **Covers R8.** With JS disabled, clicking a control submits a form and the click is
  accepted; with JS enabled, the click submits in place and the button shows a pending state.
- AE6. **Covers R15.** A bot with no webhook and no WS session posting a round-trip control
  gets `422`.

---

## Scope Boundaries

**In v1**

- Buttons (at least; whether a select is included depends on the shape decision below).
- The document on the message; server-side render; one interaction endpoint; dispatch to the
  authoring bot; bot updates via existing PATCH.
- Bots only.

**Deferred**

- **Ephemeral / "only you can see this" responses.** Sabha has no per-user message visibility;
  a genuine data-model addition.
- **Modals / dialogs** (`trigger_id` → `view_submission` lifecycle) and **input blocks /
  text fields**. The wizard pattern (each answer edits the message into the next question)
  covers most of the need.
- **Per-user selection state held by Sabha** (`selection_mode`, a selections table, "you
  already voted"). Bots track it and render it in the body. Explicitly rejected, not just
  deferred — see Prior Art.
- **Link buttons with arbitrary URL schemes.** If link buttons ship at all, `https` only.
- **Bot-supplied appearance** — hex colors, icon sets, icon-only round buttons, icon
  position. Controls use Sabha's tokens and at most a small `style` enum.
- **Human-authored documents.** Compose-box polls etc. are a separate product decision.
- **Synchronous inline reply** (bot's HTTP 200 body carries the new document). Fast-follow.
- `image`, `video`, `rich_text`, date pickers, overflow menus, checkboxes, radios, App Home,
  slash commands.

---

## Dependencies / Assumptions

- The bot message-update endpoint exists (`PATCH /api/bots/messages/:id`) and already
  re-renders and re-broadcasts; it needs only to accept the document.
- Outbound dispatch already has HMAC signing (`User::Bot::WebhookSigner`), an SSRF guard on
  webhook URLs, async delivery via `Bot::WebhookJob` (`retry_on` transient errors +
  `Webhook::DeliveryError`, polynomial backoff, 10 attempts), and a WS alternative in
  `BotEventsChannel` (tenant-scoped stream in SaaS). `Bot::EventPayload` uses an `event:`
  discriminator (`message_created`, `boost_created`, …) so a new event name slots in without
  a payload-shape change.
- The message fragment cache keys on the message record (plus a few per-viewer bits), so a
  document update busts it naturally; KD5 keeps it from needing per-user interaction state.
- No ViewComponent in the repo; rendering is ERB partials + a helper.
- Assumes bots are trusted to the degree of "can post in rooms it's a member of" — a leaked
  bot key gains the ability to post buttons, not to act as members.

---

## Outstanding Questions

**The one that gates planning**

- **OQ1. Document shape — Block Kit subset or flat `actions` list?** This was decided in the
  withdrawn plan (Block Kit subset: `section`/`actions`/`context`/`divider`/`header` blocks;
  `button`/`static_select` elements; `plain_text`/`mrkdwn` text objects). #244 makes a strong
  case for the smaller primitive. Both are compatible with KD1–KD10; they differ in surface
  and in who the schema is for.

  | | **Block Kit subset** (withdrawn plan) | **Flat `actions` list** (#244 shape) |
  |---|---|---|
  | Wire shape | `blocks: [{type, block_id, elements: [{type, action_id, text, value}]}]` | `actions: [{label, value, style}]` |
  | Who already knows it | LLM agents, ex-Slack bot authors — near-zero priming | nobody, but there's almost nothing to learn |
  | Layout surface | header/section/context/divider — some "layout ambition" | none; controls sit under the body |
  | Design-principle fit | brings the anti-reference in the door, mitigated by scope | restraint by construction |
  | Room to grow | selects, more blocks, later ephemeral/modals all have a home | select is an additive `type` later; layout would be a re-think |
  | Portability | Slack Block Kit (in spirit) | once-campfire, if #247 (or a slimmer version) merges |
  | Sprawl risk | bounded by the whitelist, but the whitelist wants to grow | #247 shows "just buttons" grew ten appearance fields in two days |
  | Rendering | partial-per-block tree | one partial |

  A middle position exists: flat `actions` **plus** an optional `text`/`context` line, no
  header/section/divider. To be decided before planning; the plan is re-derived from it.

- **OQ2. Do we want a `select` in v1?** Only meaningful under the Block Kit shape (or as an
  additive `type` in the flat one). #244 defers it; buttons cover the deploy/ack/poll cases.

- **OQ3. Should the callback include the *current* document / body?** Slack sends the whole
  message; #247 sends only ids and paths. Sending the document lets a stateless bot mutate
  and re-post without a read; sending ids keeps the payload small.

**Deferred to planning**

- Exact event name / payload builder in `Bot::EventPayload`; whether it fans out through
  `notify_bots` or a dedicated call.
- Where the interaction endpoint lives (nested under messages; naming avoids collision with
  the existing user-blocking `Block` model — `messages.blocks` / `Message::Blocks` would clash
  with `User::Blockable`).
- Pending-state UX while awaiting the bot's edit (optimistic disable, spinner, nothing).
- Rate-limit numbers; control-count and value-length caps.
- What `/skills` and `BOT_INTEGRATION.md` should show as the canonical example (deploy
  approval reads best).
- Whether to gate the feature (all bots vs. per-bot flag) — assumed all bots.

---

## Prior Art

**once-campfire (which Sabha's bot layer descends from) — the load-bearing input**

- **Discussion #244** — *"Proposal: interactive actions on bot messages"* (ronaldlokers,
  2026-08-14, Ideas). Built on #239 (bots can edit/delete their own messages, merged
  2026-08-11). The ask is one primitive: `actions: [{label, value, style}]` on a bot message;
  a click POSTs `{type: "action", room, user, message, action: {value}}` to the bot's
  webhook. Explicitly argues **against** a Block Kit-style schema: *"Slack needed one because
  third parties build against a hosted product they can't extend. Campfire users run their
  own server and write their own bots; the expressive power belongs on their side of the
  wire."* Shows polls, checklists, wizards, paginated results, claim queues and live status all
  falling out of the post → action → edit loop in ~50 lines of bot code. Puts ephemeral
  messages, modals, selects and **per-user action state** out of scope. Positions itself as
  the smaller alternative to #210 (first-class poll messages: three models, three
  controllers, three Stimulus controllers).
- **PR #247** — *"Add interactive actions to bot messages"* (same author, 2026-08-16,
  +1567/−46, 34 files, open, no maintainer response as of this writing). Implements #244 but
  sprawls well past it: 12 actions/message; `disabled`; `selection_mode: none|single|multiple`
  with a `bot_action_selections` table, a batched selections endpoint and a Stimulus controller
  that fetches per-user state on connect; link actions with any non-`javascript/data/file/
  vbscript` scheme (docs concede the scheme is caller-trusted); 26 bundled icons, emoji,
  `icon_position`, `icon_only`, `background_color` + auto-contrast `text_color`. Callback
  carries an `id` (UUID); a job retries with the same id; click returns `202 Accepted`;
  webhook response body ignored. Three migrations. Copilot review flagged the per-message
  restore fetch, N×M selection preload, empty-row accumulation.

  What we take from it: the **architecture agrees with ours** (JSON on the message, bots-only,
  fail-closed validation, nested REST click endpoint, forgery guard on the value, per-user
  rate limit, dispatch to the authoring bot only, edit-via-existing-API as the response,
  async-only, `button_to` forms). **Adopt:** the event id + same-id retries (→ KD7/R14),
  `disabled` (→ R9), `202`-style ack (→ R16), "reject round-trip controls when the bot has no
  delivery path" (→ R15). **Reject:** per-user selection state (→ KD5), arbitrary-scheme link
  buttons, bot-supplied appearance (→ KD9, scope boundaries). **Reopen:** the schema shape
  (→ OQ1) — #244's argument is good, and #247 is simultaneously the evidence that "just
  buttons" doesn't stay just buttons.

**The wider field** — the consistent shape across all of them is *label + opaque
developer-defined value + a callback carrying that value back*; everything past that is
layout ambition.

| Product | Mechanism | Callback | Complexity |
|---|---|---|---|
| Slack | Block Kit — JSON block/element tree, `action_id` per element | `block_actions` to a request URL, whole message included | very high; a UI framework with its own builder |
| Discord | Message components — action rows of buttons/selects, `custom_id` (100 chars) | interaction with `custom_id` | moderate; grew into Components v2 |
| Mattermost | `actions` array in a message attachment; each names an integration URL + `context` | POST to the integration URL | low; closest to #244, no pre-registration |
| Telegram | Inline keyboards, `callback_data` (64 bytes) | echoed to the bot | very low |
| once-campfire #247 | flat `actions` + selection modes + appearance | `type: "action"` + `id` + `selected` | started low, ended moderate |

---

## Sources / Research

- once-campfire discussion #244 —
  https://github.com/basecamp/once-campfire/discussions/244
- once-campfire PR #247 — https://github.com/basecamp/once-campfire/pull/247 (fetched
  locally as branch `pr-247` in `~/dev/once-campfire`; key files:
  `app/models/message.rb`, `app/controllers/messages/bot_actions_controller.rb`,
  `app/models/webhook.rb`, `docs/bots.md`)
- once-campfire PR #239 (bot self-edit, merged) and #210 (first-class polls, open, the
  competing shape)
- Slack Block Kit reference (blocks, elements, `block_actions` payload)
- Discord message components; Mattermost interactive messages; Telegram inline keyboards
- Sabha: `docs/features/BOT_INTEGRATION.md`, `app/views/skills/show.text.erb`,
  `app/models/bot/event_payload.rb`, `app/models/webhook.rb`, `app/jobs/bot/webhook_job.rb`,
  `app/channels/bot_events_channel.rb`, `app/controllers/api/bots/messages_controller.rb`
- Withdrawn plan: `docs/plans/2026-08-12-002-feat-block-kit-interactive-messages-plan.md`
  (removed; its architecture survives here as KD1–KD10, its schema choice is OQ1)
