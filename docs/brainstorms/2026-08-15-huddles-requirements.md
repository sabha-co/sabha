---
title: "Huddles — ephemeral in-channel voice for self-hosted Sabha"
date: 2026-08-15
topic: huddles
---

# Huddles — ephemeral in-channel voice for self-hosted Sabha

## Summary

Huddles bring ephemeral, drop-in voice to a channel: a member starts one from the room
header, others join in a click, and it ends when the last person leaves. v1 targets
Slack-Huddles parity — audio, screen-share, optional camera, and a persistent mini-bar —
for **self-hosted Sabha only**, backed by a self-hosted LiveKit media server that stays
hidden until an admin configures it.

---

## Problem Frame

Sabha is real-time text, but synchronous conversation has nowhere to go inside it. When a
thread reaches "let's just talk this out," members leave for Zoom, Discord, or Slack — and
the context leaves with them.

For teams weighing Sabha as a Slack replacement, the absence of voice is a hard stop, not a
missing nice-to-have: a team that huddles daily will not move to a tool that cannot. The bar
is parity with the specific thing they would miss — **Slack Huddles** — not a general
calling or conferencing platform.

Scope is self-hosted single-tenant, where running a media sidecar is already normal (the app
requires an `anycable-go` process) and operators control their own infrastructure. That makes
"add one more Go server" a known quantity rather than a new class of burden.

---

## Key Decisions

- KD1. **Slack-Huddles model, not Discord voice rooms or a calling platform.** Huddles are
  ephemeral, in-channel, drop-in moments — not persistent places and not telephony.

- KD2. **A huddle is a fact on the room, not a first-class call subsystem.** At most one live
  huddle per room; it starts on the first join and ends on the last leave, and it inherits
  the room's membership and access. This is chatto's "calls-as-rooms" bet — it collapses what
  could be a whole call domain into "a room that happens to have people talking in it."

- KD3. **Self-hosted LiveKit as the media backend.** Not peer-to-peer mesh (owns too much
  WebRTC surface, still needs a TURN relay for reliability) and not LiveKit Cloud (a paid
  external dependency that breaks air-gapped self-hosts). One media path; the app only mints
  join credentials and never touches media.

- KD4. **Off unless configured, and hidden rather than greyed.** With no LiveKit configured,
  the huddle affordance does not render anywhere — no disabled buttons.

- KD5. **Discovery splits by surface.** Ambient (a silent live indicator) in channels; a
  notification — never a ring — in DMs. This matches how Slack itself behaves and keeps the
  feature aligned with Sabha's low-interruption disposition.

- KD6. **One quiet recap on end.** A single timeline line when a huddle ends, not a stream of
  join/leave events. (chatto shipped join/leave timeline messages and deliberately reverted
  them.)

- KD7. **No ghost huddles.** A "live" indicator must clear when the call actually ends, even
  when a client crashes or closes without an explicit leave. The media server is the source
  of truth for who is really connected. Mechanism is a planning decision.

- KD8. **Self-host only for v1; SaaS deferred.** Multi-tenant huddles are out of scope, but
  the huddle's identity/room-naming should be chosen so a future SaaS door stays cheap to
  open — tenant isolation itself is not built now.

---

## Actors

- A1. **Starter** — a room member who opens a huddle.
- A2. **Joiner** — another room member who drops in.
- A3. **Bystander** — a room member not in the huddle; sees ambient signals, or (in a DM) a
  notification.
- A4. **Admin** — the self-host operator who deploys and configures LiveKit.
- A5. **LiveKit** — the media server; source of truth for who is actually connected.

---

## Requirements

**Lifecycle & model**

- R1. Any member who can view a room can start a huddle in it.
- R2. At most one live huddle exists per room; a second "start" joins the existing one.
- R3. A huddle starts when the first participant connects and ends when the last participant
  leaves.
- R4. A huddle inherits the room's membership and access; there is no separate huddle
  membership or access model.
- R5. Huddles are available in channels (Open, Closed) and DMs (Direct). Forums and sub-rooms
  (Threads, Posts) do not get huddles in v1.

**In-call experience**

- R6. A participant can speak (audio), share a screen, and optionally enable camera.
- R7. A participant can mute their own mic and leave the huddle.
- R8. Participants see live avatars with a subtle speaking indicator and can select input and
  output devices.
- R9. While in any huddle, a persistent mini-bar shows the current huddle and its controls
  (mute, screen-share, leave) and stays visible as the user navigates to other rooms.
- R10. A user can be in at most one huddle at a time.

**Discovery & presence**

- R11. While a channel huddle is live, the room shows an ambient live indicator to all its
  members, with current participants visible on it. No notification is sent.
- R12. When a huddle starts in a DM, the other member(s) receive a notification ("X started a
  huddle"), reusing Sabha's existing notification and push delivery and respecting existing
  notification preferences. No ring.
- R13. Channel discovery is passive: a member finds a live channel huddle by seeing the
  indicator, not by being alerted.
- R14. Screen-share and camera content are visible only to joined participants; bystanders
  see that a huddle is live and who is in it, not what is being shared.

**After the huddle**

- R15. When a huddle ends, a single recap line is posted to the channel timeline (duration
  and participants). Individual joins and leaves are not posted as timeline events.

**Configuration & reliability**

- R16. Huddles are gated on LiveKit configuration; with no LiveKit configured, no huddle
  affordance renders anywhere.
- R17. The live indicator reflects reality: it clears when the call actually ends, including
  when a participant's client disconnects without an explicit leave. No stale "live" state
  persists.
- R18. A join grants access to exactly one huddle and is short-lived; a member of one room
  cannot obtain access to another room's huddle.

---

## Key Flows

- F1. Start a channel huddle
  - **Trigger:** A1 clicks Start in the room header.
  - **Steps:** the huddle becomes live; A1 connects to media; the room's ambient indicator
    lights for every member.
  - **Outcome:** any member can one-click join.
  - **Covers:** R1, R2, R3, R11.

- F2. Join a live huddle
  - **Trigger:** A2 clicks Join on the indicator or room header.
  - **Steps:** A2 connects; the participant list and mini-bar update for those in the huddle.
  - **Covers:** R6, R7, R8, R9.

- F3. DM huddle notifies
  - **Trigger:** A1 starts a huddle in a DM.
  - **Steps:** the DM shows the ambient indicator and the other member(s) receive a "started
    a huddle" notification; no ring.
  - **Covers:** R12.

- F4. Last leave ends it
  - **Trigger:** the final participant leaves.
  - **Steps:** the huddle ends; the indicator clears; the recap line posts.
  - **Covers:** R3, R15, R17.

- F5. Crashed client
  - **Trigger:** a participant's tab closes or crashes without leaving.
  - **Steps:** the system reconciles against LiveKit truth and removes them; if they were the
    last participant, the huddle ends.
  - **Covers:** R17.

---

## Acceptance Examples

- AE1. **Covers R11, R12.** Given a live huddle: when it is in a channel, members see the
  indicator and receive no notification; when it is in a DM, the other member also receives a
  "started a huddle" notification.
- AE2. **Covers R14.** Given a live channel huddle where someone is screen-sharing: a
  bystander sees "3 in huddle" but not the shared screen or who is sharing; a joiner sees the
  screen.
- AE3. **Covers R17.** Given a two-person huddle where one participant's browser crashes:
  within a short reconciliation window the indicator drops to one participant; if the crashed
  user was the last, the huddle ends and the recap posts.
- AE4. **Covers R16.** Given LiveKit is not configured: no "Start huddle" control appears in
  any room header, and no ambient indicators occur.

---

## Scope Boundaries

**Deferred for later**

- SaaS / multi-tenant huddles (tenant-scoped media routing and isolation).
- Huddle threads — persistent in-huddle chat, links, and notes.
- Always-on end-to-end-encrypted media.
- Recording / egress.
- Background blur and noise suppression beyond browser-native defaults.
- Participant caps and large-room "stage" (request-to-speak) mode.
- Incoming-call ring for DMs (accept / decline / missed-call).
- Native mobile and desktop huddle clients.

**Outside this product's identity**

- Discord-style persistent voice rooms in the sidebar. Huddles are moments, not places.
- A telephony / ringing feel generally. Huddles invite; they do not demand.

---

## Dependencies / Assumptions

- A self-hosted LiveKit server is deployed and reachable, and the admin supplies its URL and
  API credentials. Assumption: operators who already run `anycable-go` can run LiveKit the
  same way.
- DM huddle notifications assume web-push is configured for reliable delivery when the
  recipient's client is closed; otherwise the notification is seen on next open.
- The LiveKit browser client must be delivered without a bundler (Sabha uses Importmap),
  which constrains how the SDK and any optional processors are vendored. Detail for planning.

---

## Outstanding Questions

**Deferred to planning**

- The reconciliation mechanism and window that satisfy R17 (webhooks, polling, or both).
- Whether the huddle is persisted as a record (backing the recap and any future history) or
  derived purely from media-server state.
- The huddle's room-naming scheme, chosen to keep the SaaS door open per KD8.
- Behavior if a huddle grows unexpectedly large (no cap in v1 — confirm nothing degrades).
- Where the mini-bar lives in the redesigned shell and how it coexists with the reserved
  room-header slot.
- Whether the DM notification fans out to all members of a group DM (assumed yes).

---

## Prior Art — How Others Build Calls

Five real implementations (local clones) place this decision on a spectrum from "own nothing"
to "build everything." The survey validates KD3 (self-hosted LiveKit) from every side.

| System | Media backend | Topology | Self-host / air-gap | Video + screen-share | Call record | Presence truth | App-side effort |
|---|---|---|---|---|---|---|---|
| **Zulip** | External providers (Jitsi default, BBB, Zoom, Webex, Nextcloud) | Link-out | Jitsi/BBB yes; Zoom/Webex no | provider's | none — just a link | none | trivial (sign a URL) |
| **Campsite** | HMS / 100ms (managed SaaS SFU) | Rented SFU | ✗ paid cloud + S3 | ✓ + recording, transcription, AI summary | heavily persisted | HMS webhooks | light (mint JWT + webhooks) |
| **Sabha (this plan)** | LiveKit (self-hosted SFU) | Self-hosted SFU | ✓ | ✓ | ephemeral (recap only) | LiveKit webhooks + reconciliation | light (mint JWT + webhooks) |
| **Mattermost** | Own Pion SFU + optional `rtcd` daemon | Self-hosted SFU (built) | ✓ | ✓ | plugin-owned | plugin/SFU | a separate product |
| **Buzz** | Own in-process Opus relay | Custom fan-out (no SFU) | ✓ | ✗ audio-only | ephemeral (events) | in-process (trivial) | large (own media stack) |

- **Zulip — owns no media at all.** No WebRTC/SFU code anywhere. A per-realm
  `video_chat_provider` setting (default Jitsi Meet) picks an external provider; every path just
  produces a URL and inserts it as Markdown (`[Join video call.](url)`) — the link opens in a new
  tab. No call object, no presence, no in-app call surface (`zerver/models/realms.py:647`,
  `zerver/views/video_calls.py`). This is exactly the model KD1/KD2 reject: there is nothing to
  hang an ambient indicator (R11), the mini-bar (R9), or a recap (R15) on. Apache-2.0, but the
  pattern is trivial anyway.

- **Campsite — rents a managed SFU (HMS/100ms); a Rails app like us.** The backend is thin: two
  REST calls (`create_room`, `stop_recording` in `api/lib/hms_client.rb`) and a per-user **app
  JWT** (`CallRoom#token`, role `guest`) shipped to the browser as `viewer_token`; the client SDK
  joins with it. Everything else is **webhook-driven** — `peer.join/leave.success` create/close
  `CallPeer` rows (the presence source of truth), `session.close.success` ends the `Call`. Richest
  feature set (S3 recording, transcription, LLM title + summary sections, search indexing) and it
  **rings** 1:1 DMs. But it is paid cloud + S3 + Imgix, breaks air-gap, and is CC-BY-**NC**
  (study only). It is the closest reference implementation we have for our own app-side work — same
  language, same "mint a JWT + handle webhooks" shape (see Sources).

- **Mattermost — builds its own SFU, shipped as an out-of-process plugin.** Core Mattermost has
  *no concept of calls*: the monorepo contains only extension seams (`registerCallButtonAction`,
  webapp `registry.ts:349`; a `plugins-com.mattermost.calls` store slice). The real media server
  (Pion WebRTC SFU + optional standalone `rtcd` daemon) lives in a **separate repo** and runs as a
  **separate OS process** over plugin RPC. This is the full cost of "build your own SFU" — a
  product with its own team. Source-available / AGPL (study only).

- **Buzz — custom in-process audio relay.** Simple precisely *because* it is audio-only; adding
  screen-share (R6) would force a real SFU. Detailed in the Buzz entry under Sources.

**What the survey settles.** The four alternatives bracket our choice: link-out is too little
(Zulip — cannot satisfy R9/R11/R15), managed SaaS breaks self-host (Campsite — violates KD3's
air-gap requirement), building the SFU is too much (Mattermost — a separate product), and going
custom means dropping video (Buzz — conflicts with R6). **Self-hosted off-the-shelf SFU
(LiveKit) is the correct cut.** Campsite is concrete proof the app-side integration is small and
matches KD3's "mint join credentials, never touch media" model — a token-minting method plus
webhook handlers, nothing more — and its webhook-driven presence is a direct reference for R17.
We can be *lighter* than Campsite because KD2 keeps huddles ephemeral rather than persisted.

---

## Sources / Research

- **Slack Huddles** — the parity target: ephemeral, drop-in, notify-not-ring, screen-share as
  the daily-driver feature.
- **chatto** (`github.com/chattocorp/chatto`, cloned locally) — closest prior art: a
  self-hostable LiveKit-based team chat. Load-bearing design docs in that repo:
  `docs/fdr/FDR-016-voice-calls.md` (product + UX) and
  `docs/adr/ADR-009-webhook-driven-voice-call-state.md` (state + reconciliation). Borrowed:
  calls-as-rooms, ambient discovery, the persistent mini-bar, one-recap-not-spam, and
  webhook-plus-reconciliation for no-ghost calls. License: chatto core is **AGPL-3.0** —
  study, do not copy.
- **Resenha** (`github.com/discourse/resenha`) — Discourse's Discord-style voice plugin;
  validates the sidebar-first ambient UX and the mesh-vs-LiveKit fork (it defaults to mesh; we
  chose LiveKit). License: **GPL-2.0** — study, do not copy.
- **Buzz** (`github.com/block/buzz`, cloned locally at `~/dev/buzz`, **Apache-2.0** —
  permissive, so a usable reference, not just study) — a divergent prior-art point that
  sharpens two of our decisions:
  - *A third transport fork beyond KD3.* Buzz uses neither mesh nor LiveKit: it built a
    custom WebSocket **Opus fan-out relay inside its own server** (`crates/buzz-relay/src/audio/`)
    — clients authenticate, get seated in an in-memory room, and the server copies opaque Opus
    frames between peers without decoding. No SFU. This is viable only because its scope is
    **audio-only** (soft cap ~25 peers) and does not generalize to video/screen-share — which
    is exactly why we chose LiveKit. Confirms KD3's reasoning rather than contradicting it.
  - *It sidesteps our R17/KD7 reconciliation problem entirely.* Because Buzz's media relay is
    in-process, the app server already knows who is really connected — last-leave auto-ends the
    room with no webhooks or polling. Our external-LiveKit split is what *creates* the
    ghost-huddle problem R17 must solve; useful framing for the planner weighing webhook vs
    poll reconciliation.
  - *Not a Slack-parity target.* No video, screen-share, or recording (all reserved but
    unbuilt); screen-share — our daily-driver feature — has no analog there. Buzz's real
    investment is AI agents as first-class voice participants (on-device STT/TTS); orthogonal
    to v1 and out of scope, noted only as a far-future direction.
  - *Independently validates* ephemeral-channel-with-TTL + calls-as-a-fact-on-the-room (KD2),
    lifecycle-as-Nostr-events with a quiet end rather than join/leave spam (KD6), and
    server-as-source-of-truth for presence (KD7).
- **LiveKit Ruby server SDK** (`github.com/livekit/server-sdk-ruby`, **Apache-2.0**) — join
  credential minting, room admin, and webhooks for the backend.
- **Sabha anchors for the planner** (repo-relative): `app/models/room.rb` (room STI model and
  `viewable_by?`), `app/controllers/api/cables_controller.rb` (precedent for minting a
  short-lived, access-scoped client credential), `app/models/room/presence_set.rb` (existing
  presence read), `app/channels/room_streams_channel.rb` (auto-authorized room streams),
  `config/initializers/vapid.rb` (external-service configuration pattern), `config/importmap.rb`
  (client-SDK delivery constraint).
