---
title: User Presence - Plan
type: feat
date: 2026-08-20
topic: user-presence
artifact_contract: ce-unified-plan/v1
artifact_readiness: implemented
product_contract_source: ce-brainstorm
execution: code
---

# User Presence - Plan

## Goal Capsule

- **Objective:** Add a manual user presence system so people can set themselves as Available, Away, or Do not disturb, and other members see that state as a colored dot on their avatar across the app.
- **Means:** Add a `presence` enum on `User`, resolve the avatar dot from that manual value **combined with a live activity signal** (Slack/Discord model), and add the picker to the current sidebar profile menu. The dot auto-downgrades a manually-Available user to amber after 10 minutes of no interaction (idle) and to grey when their socket is gone (offline). Live updates use **one workspace stream** in the layout (`Current.account, :presence`), carrying presence-only dot fragments, fired on manual changes **and** idle/active edges. (Per-subject streams were built first and withdrawn — see KTD3.)
- **Authority:** v2.1 design handoff (`design_handoff_sabha_v2.1`), specifically the sidebar footer flyout, DM list, recipient picker, member directory, and quick profile card surfaces.
- **Execution profile:** Feature-tier, bounded scope. The setter lives in today's `_profile_menu.html.erb` (already a popover). If v2.1 later replaces that menu, move the same three rows — do not wait on the redesign to ship.
- **Stop conditions:** The three states are selectable, persisted, and visible on every surface named below; a manually-Available user's dot auto-resolves to green (active) / amber (idle 10 min+) / grey (offline); other members' visible dots update over Turbo without a reload on both manual changes and idle edges; unit and system tests pass.

## Implementation Status

**Built and green on branch `user-presence`** (cut from `redesign-v2`, 2026-08-24). Not yet committed.

| Unit | State | Notes |
|---|---|---|
| U1 model + migrations | done | `users.availability` enum, `users.last_active_at`, `User::Presence` concern with the R4a resolver |
| U2 mapping + CSS | done | token → `status--*`; one new rule, `status--dnd` |
| U3 controller + broadcast | done | `resource :presence, only: :update`; presence-only fragment |
| U4 picker | done | in `_profile_menu.html.erb` as planned; radiogroup, DND hint, closes on success only |
| U5 surface dots | done | 8 surfaces on resolved dot + per-surface stable ids |
| U6 directory | done | batch resolve; own row and deactivated/banned rows carry no dot |
| U7 live updates | done | manual **and** idle edges, proven across two sessions |
| U8 idle watcher | done | `idle` Stimulus controller → `HeartbeatChannel#activity` |

**Verification:** 2040 unit/controller/model tests, 0 failures. `test/system/presence_test.rb` 5/5 (includes the two-session cross-user proof and a duplicate-subscription guard). `test/system/dm_split_test.rb` green. One pre-existing failure in `sidebar_navigation_test` ("View profile" link) confirmed present without these changes.

**Deviations from the plan as written**, each reasoned in place: KTD3 (per-subject → workspace stream), KTD6's channel (`PresenceChannel` → `HeartbeatChannel`), and `connected_at` left untouched despite the "re-gate the heartbeat" framing of the true-idle directive — re-gating would have starved push gating, `Room::Roster#here_now`, unread, and email-away.

**Open, deliberately:** every member receives every presence change (KTD3's accepted trade); R4f's roomless-idle gap reads as offline rather than idle; the recipient picker (R12) paints at fetch time only and is not wired to the autocomplete JSON yet.

## Product Contract

### Summary

Add a manual presence selector with three states: Available, Away, and Do not disturb. The chosen state drives a small colored dot on the user's avatar, resolved together with a live activity signal (the Slack/Discord model): Do not disturb is red, manual Away is amber. A manually-Available user resolves automatically — green when active, amber when idle (no interaction for 10 minutes while a tab is open), and grey/hollow when their socket is gone (offline). Offline greys the dot for every state, since we can no longer vouch for it. The only place to change the manual state is the profile menu opened from the sidebar footer. Presence is displayed on the sidebar footer row, one-to-one DM rows, the DM list screen, the recipient picker (at fetch time), other members' directory rows (not the current user's own row), group DM participant cards, and quick profile cards. Group DMs and multi-person avatar stacks intentionally omit the dot. Custom status text and notification suppression are not part of this slice. Do not disturb is a visible status only — notifications are unchanged. Auto-idle detection **is** in scope (it downgrades Available only); OS-level presence and scheduled/DND-on-a-timer are not.

### Problem Frame

The v2.1 redesign treats presence as a first-class social signal in the sidebar and member surfaces. The application already paints **socket-derived** `.status-dot` markers (who looks connected via `Membership::Connectable`) and has per-room AnyCable presence (who is viewing a room). It does not have a user-level, manually-set status that follows a person across rooms and DMs. This slice replaces the socket dots on the named surfaces with a **resolved** dot that combines the manual value with liveness. It reuses the existing connected tracker for the offline half (a socket being alive) and adds a **new, separate activity signal** for the idle half (a human actually interacting) — because the connection heartbeat fires on a timer, so `connected_at` proves "a tab is open," never "someone is at the keyboard." The existing `activity_statuses_for` / `connected_at` machinery is left untouched for email away logic, room presence, push gating, unread, and the online count; the new signal drives the dot only.

### Requirements

#### Core presence model

- R1. A user has one presence state at a time: `available`, `away`, or `do_not_disturb`.
- R2. The default state for a user is `available`. This is a self-reported default, not proof they are at the keyboard.
- R3. Changing presence applies immediately and is persisted to the user's record.
- R4. Presence changes are broadcast on the workspace presence stream so other members' visible dots update without a page reload.

#### Auto-idle resolution (Slack/Discord model)

- R4a. The visible dot is **resolved** from three inputs, top match wins: (1) deactivated/banned → no dot; (2) offline (no live socket) → grey/hollow; (3) manual Do not disturb → red; (4) manual Away → amber; (5) Available + idle (no interaction ≥ 10 min) → amber; (6) Available + active → green. Offline outranks manual state because we can no longer vouch for it.
- R4b. "Active" vs "idle" is detected **client-side** from real interaction (pointer, keydown, scroll, touch, tab visibility) — never from the connection heartbeat, which is a blind timer. Reported over `HeartbeatChannel` (user-level; `PresenceChannel` is room-scoped and would go deaf off-room). The idle threshold is 10 minutes, reusing `Membership::Connectable::ACTIVITY_TIERS[:active]`.
- R4c. Auto-idle only ever downgrades a manually **Available** user. Manual Away and Do not disturb are sticky while the user is online and are not auto-changed.
- R4d. Crossing the idle↔active edge is broadcast exactly like a manual change, so other members' dots update without a reload. Only edges broadcast — not every activity ping.
- R4e. The activity signal is a new, dedicated store (`users.last_active_at`); it does not alter `connected_at`, `activity_statuses_for`, room presence, push gating, unread, email away logic, or the online count.
- R4f. Reachability reads as "a live room connection **or** a recent interaction". The room heartbeat only speaks while someone is watching a room, so on its own it files anyone reading their settings as offline. Known gap: a tab parked on a roomless page long enough to go idle reads as offline rather than idle.

#### Setting presence

- R5. The profile menu opened from the sidebar footer contains a "Presence" section with the three options. Until v2.1 lands, that menu is `app/views/users/sidebars/_profile_menu.html.erb`.
- R6. The selected option is visually highlighted; the other two are unselected. Options are a keyboard-operable radiogroup (arrow keys, Enter/Space). Re-tapping the already-selected state still closes the menu.
- R7. Tapping an option sets presence immediately and closes the menu on **success**. While the request is in flight, the three options are disabled. On 422 / failure the menu stays open, the previous selection remains highlighted, and the failed option is not shown as selected.
- R8. No separate save or confirmation step is required.
- R8a. Compact/icon-rail footer still opens the same menu from the avatar. The state **label** may hide in the rail; the dot remains visible. Honor `prefers-reduced-motion` on open/close.

#### Displaying presence

- R9. The current user's sidebar footer row shows their own presence dot and state label (e.g., "Available", "Away", "Do not disturb"). The label replaces the email subline on the expanded footer, not beside it.
- R10. One-to-one DM rows in the sidebar show the other person's presence dot.
- R11. The DM list screen shows the other person's presence dot on each solo DM row.
- R12. The recipient picker shows each candidate's presence dot next to their avatar while filtering. Paint the dot from the autocomplete JSON at fetch time. Open suggestion lists do **not** update live (no Turbo subscription).
- R13. The member directory shows each **other** member's presence dot and a status subline that reflects the **resolved** token, so text and dot never disagree: "Available" (active), "Away" (manual away or idle), "Do not disturb", "Offline". Do not use "Here now". Presence **replaces** the joined-date subline on those rows.
- R14. The group DM participants panel shows each participant's presence dot and status subline (same resolved labels as R13).
- R15. Quick profile cards show the person's presence dot and status subline (same resolved labels as R13).
- R16. Group DM avatar stacks and group DM rows omit the presence dot; the header or row subline names the participants instead. Keep the existing `members.many?` (or equivalent) gate.

#### Visual treatment

- R17. Available/active uses the semantic positive color (`--color-positive`) — reuse `status--active`.
- R18. Away (manual) and idle (auto) both use the semantic alert/away color (`--color-alert`) — reuse `status--away`.
- R19. Do not disturb uses the semantic negative color (`--color-negative`) — new `status--dnd` class.
- R19a. Offline uses the muted/subtle treatment — reuse the existing `status--offline` (grey/hollow). It applies whenever there is no live socket, regardless of manual state (except deactivated/banned, which show no dot per R21).
- R20. The dot is 8px, circular, and positioned at the bottom-right edge of the avatar using the existing sibling `.status-dot` markup. `avatar_image_tag` does not wrap the dot.
- R21. Deactivated or banned users do not show a presence dot; their existing status chip remains visible.
- R21a. Color-only dots (DM rows, recipient picker) expose an accessible name (`aria-label` on the dot or a visually hidden label). Do not leave them `aria-hidden` with no alternative.

#### States that are explicitly not scope

- R22. Custom status text ("What are you up to?") is not included.
- R23. Tab-open idle detection **is** included (R4a–R4e). What remains out of scope: OS-level idle, scheduled/timed DND, and any idle threshold that is user-configurable — the threshold is a fixed 10 minutes.
- R24. Do not disturb does not suppress notifications. The picker must say so in copy (e.g. a hint under the DND row: "Notifications are unchanged"). DND is a visible status, not a quiet mode.
- R25. Presence is not shown in room member rosters.
- R26. The current user's own row in the Members directory does not show their presence.

### Actors

- A1. **Workspace member** — any signed-in user who can see the sidebar, DMs, member directory, and recipient picker.
- A2. **Other members** — people whose avatars the member sees; they do not need to take any action.

### Key Flows

- F1. Setting presence
  - **Trigger:** The member clicks their footer row in the sidebar to open the profile menu.
  - **Actors:** A1.
  - **Steps:**
    1. Menu opens with a Presence section showing Available, Away, and Do not disturb.
    2. Member taps the desired state (or the already-selected state).
    3. Presence is persisted and broadcast to `user, :presence`.
    4. Menu closes on success.
  - **Outcome:** The member's avatar dot updates everywhere they appear, including their own footer row and other members' open views of them.

- F2. Seeing presence in a DM
  - **Trigger:** A member opens the sidebar or the DM list.
  - **Actors:** A1, A2.
  - **Steps:**
    1. For each one-to-one DM, the app reads the other user's persisted `presence`.
    2. The avatar renders with the matching dot.
  - **Outcome:** Members can scan the DM list to see each person's **self-reported** state, not whether they are at the keyboard.

### Acceptance Examples

- AE1. Given a member sets themselves to Away, when another member opens a one-to-one DM with them, then the DM row shows an amber dot.
- AE2. Given a member sets themselves to Do not disturb, when their avatar appears in a quick profile card, then the card shows a red dot.
- AE3. Given a group DM with three members, when the header avatar stack renders, then no presence dot appears on the stack.
- AE4. Given a member is deactivated or banned, when they appear in the member directory, then their row uses the deactivated/banned chip and does not show a presence dot.
- AE5. Given member Alice is on Bob's DM list, when Alice sets Away in another session, then Bob's DM row updates to amber without a reload.
- AE6. Given a member sets Do not disturb, when a mention notification would fire, then it still fires.
- AE7. Given a member is Available and has not interacted for 10 minutes with a tab open, when another member views their dot, then it shows amber (idle); when the member moves the mouse, it returns to green without a reload.
- AE8. Given a member is Available and closes their last tab, when another member views their dot, then it shows grey (offline) on the next render.
- AE9. Given a member sets Do not disturb and then goes idle, when another member views their dot, then it stays red — idle does not override a manual state.

### Scope Boundaries

- **Deferred for later:** custom status text, DND notification suppression, room member roster presence, presence on the current user's own member-directory row, a configurable idle threshold, and OS-level/scheduled idle.
- **Outside this feature's identity:** huddles, audio/video status, typing indicators, and read receipts. These are separate real-time signals.

### Dependencies / Assumptions

- The current sidebar profile menu (`_profile_menu.html.erb`) is the setter. v2.1 may restyle or rename that flyout later; this slice does not block on it.
- AnyCable already terminates WebSockets. Presence live updates reuse Turbo Streams over that socket. No new WebSocket server or ActionCable channel class.
- Presence is a dedicated `users.availability` column (not a preferences key), plus a `users.last_active_at` timestamp for the idle signal. No database index in this slice — nothing filters or sorts by either.
- Auto-idle needs the browser to report interaction; the connection heartbeat cannot (it is a timer). The idle watcher piggybacks the existing `PresenceChannel`; `connected_at` is not re-gated.
- SaaS: `User` is tenanted; add the column via the usual tenanted `db/migrate` path, not an untenanted migration.

### Outstanding Questions

- None. Fan-out is one workspace stream (KTD3). Directory copy is "Available", not "Here now". DND is status-only with explicit copy. Auto-idle (Slack/Discord model) downgrades Available only, via a separate `last_active_at` signal and a fixed 10-minute threshold; offline greys all states; the connection heartbeat is untouched.

## Planning Contract

### Key Technical Decisions

- KTD1. Store presence as a `User` enum column (`available`, `away`, `do_not_disturb`), default `available`, `null: false` so existing rows backfill. **Named `availability`, not `presence`** — `presence` is `Object#presence` on every model, and an attribute by that name shadows the present?-or-nil idiom for the life of the codebase. Availability is what someone chose; presence is what it resolves to. Not inside `preferences`. Do **not** add an index. Governs R1–R4.
- KTD2. The dot is **resolved** from manual presence + liveness (offline) + a new activity signal (idle), via a single explicit resolver (KTD7) — the deliberate Slack/Discord merge. This supersedes the earlier "manual value alone drives the dot." What stays separate: the resolver does **not** overload `activity_statuses_for` or `connected_at`. That existing socket machinery keeps feeding email away logic, room presence, push gating, unread, and the "online" count, untouched. Manual state still wins over the active/idle distinction while the user is online; offline outranks manual. Governs R2, R4a, R13, R21.
- KTD3. **Workspace stream.** One `turbo_stream_from Current.account, :presence` in the application layout, rendered exactly once per page; broadcasts go to `[Current.account, :presence]`. Payload stays a **presence-only fragment** (dot + label), never a full DM row, directory row, or quick-profile card (those contain viewer-specific admin controls and unread). Governs R4.

  **This replaces the original per-subject stream** (`turbo_stream_from user, :presence` beside each dot), which was implemented and then withdrawn as unshippable. Per-subject subscriptions are the tighter fan-out, but the same person's dot renders in both the sidebar frame and the main document — two separate HTTP renders that cannot dedupe against each other. Action Cable answers a duplicate `subscribe` with `return if subscriptions.key?(id_key)`, so no second confirmation is sent. Measured against the current code, which has **zero** duplicate subscriptions on every page checked, the per-subject design introduced 2 duplicates on the DM inbox, 3 on the members directory, and 2 on a DM room, plus `visit`-time failures in unrelated system tests (`dm_split_test`).

  **Correction (2026-08-25):** this entry originally claimed the duplicate was never confirmed and left `SubscriptionGuarantor` resubscribing every 500ms for the life of the tab. That is wrong. `confirmSubscription(identifier)` forgets *every* subscription sharing the identifier via `findAll`, and `remove` only sends `unsubscribe` once the last one is gone — so duplicates are wasteful, not self-perpetuating. Verified in the Action Cable source and measured: a room page carrying three identical `HeartbeatChannel` subscriptions sends zero frames in a five-second idle window. The workspace-stream decision still stands, but on fan-out grounds (see the delivery split), not this one.
- KTD4. Reuse the existing sibling `.status-dot` markup and CSS, in a `PresencesHelper` of its own rather than bolted onto `AccountsHelper`. Give the dot its own class map including `do_not_disturb` (and map `available` — do not reuse `:active`, which already means account lifecycle on `User` and socket activity on `Membership`). `avatar_image_tag` stays an `<img>`; wrap or sibling-render the dot in the views. Governs R17–R20.
- KTD5. Directory batch-reads all three inputs to avoid N+1: `users.availability`, the connected set (existing `Membership.connected` scope), and the active set (`User.where(last_active_at: 10.min.ago..)`), then resolves per row (KTD7). Do **not** teach the old socket-status helpers to fall back to manual presence — the resolver is a separate path. `@activity_statuses` survives only where it answers a question about connections (the directory sort and the online count); once every dot read the resolver, `activity_status_class`/`online_status_class` had no callers left and were deleted. Governs R13.

- KTD6. **Activity signal.** Add `last_active_at` to `users` (not `memberships` — the dot is user-level). A client-side idle watcher (Stimulus, mounted on `<body>`) tracks real interaction and reports only edges over the **existing `HeartbeatChannel`** (new `activity` action); no new channel class. Not `PresenceChannel`: that one subclasses `RoomChannel` and rejects a subscription without a `room_id`, so it would stop hearing from anyone reading their settings. `HeartbeatChannel` is per-user and already subscribed app-wide as the connection-liveness proxy. The server bumps `last_active_at` on "active" pings — throttled like the connection heartbeat (only rewrite once stale, to protect the single SQLite writer) — and on either edge persists + broadcasts the presence fragment (KTD3). **Do not** re-gate `refresh_connection`/`connected_at` on interaction: that column is liveness for push gating (`message.rb`), `Room::Roster#here_now`, `Membership::Unreadable`, and email away — starving it would make an idle-but-open tab look disconnected and start pushing to it. Governs R4b, R4d, R4e.

- KTD7. **Dot resolver.** One method (e.g. `User#presence_dot` + a batch form) returns the resolved token from `(manual_presence, connected?, active?)` with the R4a ladder: deactivated/banned → `nil`; `!connected` → `:offline`; `dnd` → `:dnd`; `away` → `:away`; `available && !active` → `:idle`; else `:active`. The current user's own row is `connected: true, active: true` (they are literally interacting), so it shows their manual state. Helpers map the token to a `status--*` class + label. Reuse `ACTIVITY_TIERS[:active]` (10 min) for the active window. Governs R4a, R4c, R17–R19a.

### High-Level Technical Design

Add `availability` to `users` as an enum: `available`, `away`, `do_not_disturb`, default `available`, and `last_active_at` (timestamp, nullable) for the activity signal. Do not add `User#presence_status` returning `:active`/`:offline` — instead add a resolver `User#presence_dot` (KTD7) that folds manual presence together with `connected?` and `active?` (`last_active_at >= 10.min.ago`) into one token. Helpers map the token to a `status--*` class + label, returning `nil` when `deactivated?`/`banned?`.

Idle is detected in the browser: a Stimulus idle watcher listens to pointer/keydown/scroll/touch/visibility, holds a 10-minute inactivity timer, and reports **edges** (went idle / came back) over the existing `PresenceChannel`. The channel bumps `last_active_at` (throttled) and, on an edge, broadcasts the presence fragment to `user, :presence`. The connection heartbeat and `connected_at` are unchanged — offline is still read from the existing `Membership.connected` scope.

`Users::PresencesController#update` (singular `resource :presence, only: :update` under the current-user scope) permits **only** `:presence`, assigns `Current.user`, and ignores any `:id`/`:user_id` in the route. On success it broadcasts a presence-only Turbo Stream to `Current.user, :presence` (here `Current.user` **is** the subject). HTML clients get a redirect back. Invalid values return 422.

Views that already render `status-dot` from socket activity **replace** that class source with the resolved dot (`User#presence_dot`). Group stacks keep skipping the dot via `members.many?`.

Recipient-picker dots are added to the autocomplete JSON and painted in `app/javascript/lib/autocomplete/renderer.js` at fetch time only.

### Implementation Units

#### U1. Database migration and User model
- **Goal:** Add and validate the presence enum, add the activity timestamp, and add the dot resolver.
- **Files:** `db/migrate/..._add_presence_to_users.rb`, `db/migrate/..._add_last_active_at_to_users.rb`, `app/models/user.rb`.
- **Patterns:** Rails enum; default `available`; `null: false`; no index. `last_active_at` is a nullable timestamp (no index in this slice). `User#presence_dot(connected:, active:)` and a batch form implement the KTD7 ladder; `active?` is `last_active_at && last_active_at >= ACTIVITY_TIERS[:active].ago`. Tenanted migration (SaaS uses the same `db/migrate`).
- **Test scenarios (test/models/user_test.rb):**
  - Default presence is `available`.
  - Valid values are accepted; invalid values are rejected.
  - Deactivated/banned users still persist a presence value; the resolver returns `nil` so no dot renders (R21).
  - `presence_dot` ladder: offline→`:offline` regardless of manual; DND→`:dnd`; manual away→`:away`; available+idle→`:idle`; available+active→`:active`.

#### U2. Presence mapping and CSS
- **Goal:** Map presence values to CSS classes, colors, and readable labels without a new helper module.
- **Files:** `app/helpers/accounts_helper.rb`, `app/assets/stylesheets/application/panels.css`. Add `avatars.css` only if positioning is missing from the current avatar component.
- **Patterns:** Map the resolved token (KTD7), not the raw manual value: `:active`→`status--active`, `:idle`/`:away`→`status--away`, `:dnd`→new `status--dnd`, `:offline`→existing `status--offline`. Add the `status--dnd` rule (`--color-negative`) in CSS. Labels: "Available" (active), "Away" (manual away **or** idle — same amber, same word), "Do not disturb", "Offline". Return no class/label for deactivated/banned.
- **Test scenarios (test/helpers/accounts_helper_test.rb):**
  - `:active` → positive dot, "Available" label.
  - `:idle` and `:away` → alert dot, "Away" label.
  - `:dnd` → negative dot, "Do not disturb" label.
  - `:offline` → muted `status--offline`.
  - Deactivated/banned users return no presence dot and retain their existing status chip.

#### U3. Presence update controller and broadcast
- **Goal:** Accept presence changes and push a presence-only fragment on the workspace stream.
- **Files:** `app/controllers/users/presences_controller.rb` (new), `config/routes.rb`, `app/views/users/presences/update.turbo_stream.erb` (new), `app/views/users/presences/_dot.html.erb` (or equivalent fragment).
- **Patterns:** Singular `resource :presence, only: :update`. `params.require(:user).permit(:presence)` (or a single `:presence` param). Update only `Current.user`. `broadcast_replace_to user, :presence` targeting stable presence fragment ids (e.g. `dom_id(user, :presence_dot)`), not full rows. HTML format: redirect back. Do not copy `Users::ProfilesController` permitted attributes.
- **Test scenarios (test/controllers/users/presences_controller_test.rb):**
  - Signed-in user can set presence to each valid state.
  - Invalid presence returns unprocessable entity; extra user attributes in the same request are not written.
  - Update broadcasts to `user, :presence` (the subject).
  - Other users cannot update someone else's presence (no user id in the route).

#### U4. Sidebar footer profile menu picker
- **Goal:** Add the picker to the existing profile menu.
- **Files:** `app/views/users/sidebars/_profile_menu.html.erb`, `app/views/users/sidebars/show.html.erb`. Reuse the existing `popover` controller. Do **not** add `_profile_flyout.html.erb` or `profile_flyout_controller.js`.
- **Patterns:** Three radio-like rows in the existing popover; `button_to` / `form_with` PATCH to `user_presence_path`; disable options while submitting; close popover on success (existing popover hide); leave open on 422. DND row includes the notifications-unchanged hint. Footer hardcoded `status--active` binds to `Current.user.presence`.
- **Test scenarios:** View tests for markup, selected state, DND hint, and radiogroup semantics. System tests for open → choose → close → footer dot.

#### U5. Replace socket dots on user avatars
- **Goal:** Show the manual presence dot on all required one-to-one surfaces **and** on group DM participant cards; skip group stacks/rows.
- **Files:** `app/views/users/sidebars/_profile_menu.html.erb`, `app/views/users/sidebars/rooms/_direct.html.erb`, `app/views/inboxes/direct_messages/_conversation.html.erb`, `app/views/rooms/show/_nav.html.erb` (1:1 DM nav dot if in scope of R10), `app/javascript/lib/autocomplete/renderer.js` plus autocomplete user JSON, `app/views/users/_quick_profile.html.erb`, `app/views/users/show.html.erb`, `app/views/rooms/directs/_participants.html.erb`. `app/helpers/users/avatars_helper.rb` only if a small wrapper is needed; do not claim `avatar_image_tag` positions the dot.
- **Patterns:** Replace `status--<%= activity %>` / hardcoded `status--active` with the **resolved** dot class (`User#presence_dot` → helper), passing the batched connected/active sets so it reflects offline and idle, not just manual state. Skip the dot when `members.many?` (R16). No per-dot subscription — the layout's workspace stream covers every surface (KTD3). Accessible name on color-only dots.
- **Test scenarios:**
  - View tests assert the correct `status-dot` class for each state on footer, 1:1 DM rows, DM list, participants, quick profile, user show.
  - Group DM rows and stacks do not render a dot.
  - Recipient picker JSON/renderer includes the dot class at fetch time.

#### U6. Member directory presence
- **Goal:** Show presence dot and status subline in the members list from persisted `presence`.
- **Files:** `app/controllers/accounts/users_controller.rb`, `app/helpers/accounts_helper.rb`, `app/views/accounts/users/_user.html.erb`.
- **Patterns:** Batch-read the three resolver inputs (KTD5): `users.availability`, the connected set, the active set. Resolve per row via `User#presence_dot`. This is a separate path from `@activity_statuses` (which stays for the sort and the online count). Omit dot and subline on the current user's own row (R26) and on deactivated/banned rows (R21).
- **Test scenarios (test/controllers/accounts/users_controller_test.rb):**
  - Member list shows correct resolved classes for available-active / available-idle / away / dnd users.
  - A manually-Available user with a stale `last_active_at` resolves to `:idle` (amber), not `:active`.
  - A user with no live socket resolves to `:offline` (grey) regardless of manual state.
  - Current user's own row in the directory does not show presence (R26).
  - Deactivated/banned rows show status chips, not presence dots.
  - Socket-online + `do_not_disturb` shows the DND class, not `status--active`.

#### U7. Real-time updates across surfaces
- **Goal:** Update visible presence fragments when the subject changes presence **or crosses the idle/active edge**.
- **Files:** shared presence fragment from U3; the single `turbo_stream_from Current.account, :presence` in `app/views/layouts/application.html.erb`. Each dot carries a per-surface stable id (`presence_dot_<surface>_<user_id>`) so one broadcast can replay every surface and Turbo drops the actions whose target isn't on screen.
- **Patterns:** Broadcast the resolved fragment to `user, :presence` from both the manual update (U3) and the activity edge (U8). Live targets: sidebar footer, one-to-one DM rows, DM list rows, member-directory rows, group-DM participant cards, open quick-profile cards, user show hero dot. **Not** recipient-picker results. Note offline transitions have no explicit broadcaster in this slice (a dead socket sends nothing) — offline is reflected on the next server render; live edges cover manual + idle only.
- **Test scenarios (system tests with two sessions):**
  - Alice sets Away; Bob's 1:1 DM row, DM list row, directory row, and open quick profile of Alice update without reload.
  - Alice goes idle (simulate the edge); Bob's dot for Alice turns amber without reload. Alice interacts again; it returns to green.
  - Alice's own footer updates without reload.
  - Recipient picker open list does not need to change until the next fetch.

#### U8. Client idle watcher and activity signal
- **Goal:** Detect real interaction in the browser and drive the idle/active edge to the server.
- **Files:** `app/javascript/controllers/idle_controller.js` (new), mounted app-wide (e.g. on `<body>` in the main layout); `app/channels/presence_channel.rb` (add `activity` action); `app/models/user.rb` (`touch_activity!` / edge helper). Reuse the existing cable consumer — no new channel class.
- **Patterns:** Listen to `pointermove`/`keydown`/`scroll`/`touchstart`/`visibilitychange`, debounced. Hold a 10-minute inactivity timer; on expiry report `active: false`, on the next interaction after idle report `active: true`. Throttle "active" pings client-side so the server sees at most one every ~1–2 min. Server: bump `last_active_at` (throttled write, mirror `CONNECTION_REFRESH_THRESHOLD`); on an edge, persist and `broadcast_replace_to user, :presence` the resolved fragment. Honor `prefers-reduced-motion` is N/A here (no animation); do honor tab-hidden as an idle accelerant only if cheap.
- **Test scenarios:**
  - Model: `touch_activity!` is throttled (no write when `last_active_at` is fresh) and always writes/marks an edge on idle→active.
  - Channel: an `activity` message with `active: false` marks the user idle and broadcasts; `active: true` after idle broadcasts the return.
  - System: the two-session idle test in U7 exercises the watcher end to end.

### Sequencing

1. U1 → U2 (model, resolver, and mapping are foundational).
2. U3 (controller + subject broadcast) can follow U1.
3. U4 mounts on `_profile_menu.html.erb` now; v2.1 is a later move of the same rows.
4. U5 and U6 are independent once U2 exists; they render the resolved class and per-surface dot ids (no per-dot subscription).
5. U8 (idle watcher + activity signal) follows U1; it reuses U3's broadcast path.
6. U7 is the two-session proof of U3+U5+U6+U8 (manual **and** idle edges); do it last.

### Risks and Mitigations

- **Resolved:** per-visible-user subscriptions were tried and withdrawn — see KTD3. One workspace stream in the layout; a system test asserts the assembled DOM has no duplicate `turbo-cable-stream-source`, since a duplicate resubscribes forever and is invisible to any single response.
- **Risk:** Existing socket dots and new manual presence diverge (e.g. manually Available, socket offline).
  - **Mitigation:** Manual status is authoritative for UI dots. Socket status remains email/push/"online" count. Copy says Available, not "Here now". AE5/AE6 cover live update and DND-does-not-mute.
- **Risk:** Broadcasting full rows leaks viewer-specific HTML.
  - **Mitigation:** Replace only presence fragments with stable ids.
- **Risk:** `_direct.html.erb` fragment caching omits presence from the cache key.
  - **Mitigation:** Include the resolved dot token (or `user.presence` + `last_active_at` + connected flag) in any cache key that wraps a dot, or bypass cache for that node.
- **Risk:** Activity pings amplify writes against the single SQLite writer.
  - **Mitigation:** Throttle client-side (one "active" ping per ~1–2 min) and server-side (only rewrite `last_active_at` once stale, mirroring `CONNECTION_REFRESH_THRESHOLD`). Only idle/active **edges** force a write + broadcast.
- **Risk:** Re-gating the connection heartbeat on interaction would break liveness.
  - **Mitigation:** Do not touch `refresh_connection`/`connected_at`. Idle is a separate `last_active_at` signal; `connected_at` stays pure liveness for push gating, room roster, unread, and email away (KTD6).
- **Risk:** Offline has no live broadcaster (a dead socket sends nothing), so a closed-tab user can show their last state until the next server render.
  - **Mitigation:** Accept for this slice — the dot corrects on any re-render, and the broker's presence TTL already bounds staleness for room-level signals. A server-side sweep to broadcast offline edges is out of scope.

### Dependencies

- Existing AnyCable + Turbo Stream stack.
- Current `_profile_menu.html.erb` popover.
- Existing `.status-dot` CSS in `panels.css`.

## Verification Contract

### Test Commands

- `bin/rails test test/models/user_test.rb test/helpers/accounts_helper_test.rb test/controllers/users/presences_controller_test.rb test/controllers/accounts/users_controller_test.rb test/channels/presence_channel_test.rb`
- `bin/rails test test/system/presence_test.rb` (two-session live update + idle edge + picker).

### Definition of Done

- A user can set presence to Available, Away, or Do not disturb from the sidebar profile menu.
- The chosen state persists across page loads.
- A manually-Available user's dot resolves to green (active), amber (idle 10 min+), or grey (offline); manual Away/DND are shown while online and greyed when offline (AE7–AE9).
- The dot updates in real time on manual changes **and** idle/active edges, on the current user's footer row, one-to-one DM rows, the DM list, member directory, group DM participants panel, and quick profile cards — including **another member's** session (AE5, AE7).
- Recipient picker shows the dot on the next fetch, not via live Turbo replace.
- Group DMs and avatar stacks never show a presence dot.
- DND does not suppress notifications; the picker copy says so.
- Directory/profile sublines say "Available", never "Here now".
- All new code has corresponding model, helper, controller, and view tests.
- `bin/rails test` passes for the affected test files.

## Appendix

### Product Contract preservation

Product contract updated from document review: subject-stream fan-out; Available copy; DND status-only with hint; setter is `_profile_menu.html.erb`; live picker dropped; mechanical summary/R11/R26/U5-goal fixes.

Two decisions were reversed during implementation, both recorded above: KTD3 (per-subject streams → one workspace stream, after per-subject was built and measured to introduce permanent duplicate subscriptions) and KTD6's channel (`PresenceChannel` → `HeartbeatChannel`, since the former is room-scoped and goes deaf off-room).

Auto-idle added after review (owner directive: match Slack/Discord). The dot is now resolved from manual presence + liveness + a new `last_active_at` activity signal (R4a–R4e, KTD6–KTD7, U8). This intentionally supersedes the earlier KTD2 "manual value alone drives the dot" and reverses the earlier "idle detection is out of scope" (former R23) — but the connection heartbeat / `activity_statuses_for` machinery is left untouched for email, room presence, push gating, unread, and the online count.

### Sources / Research

- Existing per-room presence: `app/channels/presence_channel.rb`, `app/models/room/presence_set.rb`.
- Socket-derived activity: `app/models/membership/connectable.rb`, `app/helpers/accounts_helper.rb`.
- Observer-private Turbo streams: `app/views/users/sidebars/show.html.erb` (`Current.user, :rooms`).
- Avatar rendering: `app/helpers/users/avatars_helper.rb`, `app/assets/stylesheets/application/avatars.css`.
- Status dot CSS: `app/assets/stylesheets/application/panels.css`.
- Sidebar footer: `app/views/users/sidebars/show.html.erb`, `app/views/users/sidebars/_profile_menu.html.erb`.
- DM rows: `app/views/users/sidebars/rooms/_direct.html.erb`, `app/views/inboxes/direct_messages/_conversation.html.erb`.
- Recipient picker: `app/views/autocompletable/users/_user.json.jbuilder`, `app/javascript/lib/autocomplete/renderer.js`.
- Member directory: `app/controllers/accounts/users_controller.rb`, `app/views/accounts/users/_user.html.erb`, `app/views/accounts/users/index.html.erb`.
- Quick profile: `app/views/users/_quick_profile.html.erb`, `app/controllers/messages/profiles_controller.rb`.
- Group DM participants: `app/views/rooms/directs/_participants.html.erb`.
- v2.1 design handoff: `design_handoff_sabha_v2.1/Sabha v2.1 Sidebar.dc.html`, `Sabha Desktop v2.1.dc.html`, `Sabha v2 Component Redlines.dc.html`, `CHANGELOG-v2.1.md`.
