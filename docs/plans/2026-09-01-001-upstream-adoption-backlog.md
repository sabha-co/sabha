# Upstream adoption backlog — Campfire & Fizzy

**Date:** 2026-09-01 · **Status:** living backlog · **Sources:** local clones
`~/dev/once-campfire` and `~/dev/fizzy`

Sabha descends from Campfire and shares an architecture with Fizzy (Rails 8.2
edge, a SaaS engine over a shared chat/tracker core, Lexxy, Active Storage,
self-hosted + SaaS). Both upstreams ran a security-hardening sprint over the
last two months. This doc records what was reviewed, what already applies, and
what is left to adopt — checked against `redesign-v2`.

Upstream PR numbers below are for tracing the reference implementation in the
clones, not links a reader must resolve.

## Done

- **SSRF address policy → surfguard** (Campfire #241 / Fizzy #3026). Replaced the
  hand-rolled `SsrfProtection` (which missed SIIT, NAT64, 6to4, and IPv6
  benchmark/doc ranges — several reaching cloud-metadata endpoints) with the
  maintained `surfguard` gem behind a `RestrictedHTTP::PrivateNetworkGuard`
  shim. Merged to `main` and forward-merged into `redesign-v2`.

## Tier 1 — confirmed security gaps, small, near-drop-in

### 1. Close cable connections on sign-out — Campfire #268 / Fizzy #3093
A WebSocket is authorized once at the handshake and never re-checked. Sign-out
destroys the session but does not close the live socket, so it keeps
authorizing subscriptions and delivering frames as the signed-out user until it
happens to drop. Sharper here because sockets are JWT-identified and skip the
reconnect RPC.

- **State:** `app/controllers/concerns/authentication.rb#terminate_current_session`
  does not close sockets. The `User#close_remote_connections` /
  `reset_remote_connections(reconnect: true)` primitive already exists — it is
  just not wired to sign-out.
- **Port:** call the close (with `reconnect: true`) from the sign-out path.
  Campfire's fix is ~7 lines in the descendant of this same file.
- **Effort:** small. **Reference:** `~/dev/once-campfire`, PR #268.

### 2. `SanitizeAttributes` message filter — Campfire #237
`ContentFilters::SanitizeTags` removes disallowed *tags* but lets *attributes*
on allowed tags pass through, so an event-handler attribute or a `javascript:`
URI on a permitted element survives, backed only by CSP. Stored-XSS
defense-in-depth in an app where messages are the product.

- **State:** no attribute-scrubbing filter; presentation chain is
  `RemoveSoloUnfurledLinkText → … → SanitizeTags` with no attribute pass.
- **Port:** add a `SanitizeAttributes` filter (~47 lines) running Rails'
  safe-list sanitizer after `SanitizeTags`, reusing the existing `ALLOWED_TAGS`
  so the tag pass is a no-op and only attributes are scrubbed. Use a dedicated
  sanitizer instance (the shared ActionText one is mutated per call).
- **Effort:** small. **Reference:** `~/dev/once-campfire`, PR #237.

## Tier 2 — worthwhile, low effort

### 3. Lexxy — done
Already on 0.9.31 (the Gemfile floor `~> 0.9.24` never held it back). The
version constraint has been dropped so the gem floats to latest; no pin.

### 4. `SECURITY.md` self-hosted trust model — Campfire #230
We have none. Given the dual self-hosted/SaaS split, document what "trusted"
means in each mode. Doc-only.

## Tier 3 — larger / needs a decision

### 5. HotCell media isolation — Fizzy #3034 (required for SaaS deploys there)
Isolates untrusted media processing (libvips/ImageMagick/ffmpeg) into an
unprivileged sidecar so a malicious upload can't reach DB credentials, secrets,
or the internal network. Right shape for the SaaS tier and open self-hosted
communities; adds a real ops surface (sidecar container, socket volume). We
already run a Kamal accessory (anycable-go) and meet the Rails 8.2 floor, so
adoption is cheap later. Verify the descriptor-passing model works with the
`activerecord-tenanted` per-workspace Active Storage layout before trusting it
in SaaS. Track; adopt only if uploads are treated as hostile.

### 6. Turbo morphing + Stimulus listener-leak audit — Fizzy
"Morph title/description on broadcast refreshes" and "stop leaking event
listeners across Stimulus connect/disconnect" are the class of bug our
message/room broadcasts are prone to. Targeted audit, not a mechanical port.

### 7. Dev tooling — Fizzy
Declarative `bin/setup` via a mise task graph, `prek` pre-commit hooks, and a
`bundle-drift` CI check (we maintain the same dual-lockfile setup and recently
hit a stale-lock nag). Quality-of-life.

## Reviewed — already covered or not applicable

- **Active Storage direct-upload auth** (Campfire #267) — covered by
  `config/initializers/direct_uploads.rb`.
- **Subscribe-time stream authorization** (Campfire, Aug 3 cluster) —
  `room_channel.rb` checks `viewable_by?` and rejects; inbox channels scope to
  `current_user`.
- **libvips unfuzzed operations** (Campfire #226) — `config/initializers/vips.rb`
  is ahead: `Vips.block_untrusted(true)`, version guard, and also blocks
  OpenSlide.
- **Bot self-manage own messages / auto note-generation** (Campfire) —
  bot-model-dependent and tracker-specific; skip unless the bot-edit behavior is
  wanted.
- **ONCE backup/restore hooks** (Campfire) — ONCE-specific; we deploy via Kamal.

## Recommendation

Do Tier 1 now — both are genuine security holes, both are small, both have a
reference implementation in `~/dev/once-campfire`. Two separate commits on
`redesign-v2`, each with the ported test. Tier 2 next; Tier 3 as capacity and
product direction allow.
