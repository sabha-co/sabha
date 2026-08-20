# Plan: Sabha v2 redesign — Phase 4 (v2.1 adoption)

**Status:** in progress — WS1–WS6 shipped; WS8 authorization-routing audit + WS9–WS11 (group-DM panel, own-profile Edit, sidebar DM names) next · **Date:** 2026-08-19 · **Builds on:** Phase 3 (`redesign-v2`, complete, unpushed) · **Source of truth:** `~/dev/design_handoff_sabha_v2.1` (the v2 bundle is frozen; build from v2.1)

> **What this is.** The designer shipped a v2.1 bundle superseding v2: a feature cut, dead affordances removed, every settings pane re-audited against its controller's permitted params, and all overflow menus converted to anchored dropdowns. The bundle was audited against `main`; we build on `redesign-v2`, which has already shipped a substantial share of what v2.1 believes is new. A three-way verification sweep (2026-08-19) checked every repo claim in `CHANGELOG-v2.1.md` against the branch — the corrections are folded in below and collected in the appendix. Phase 4 closes the true delta. When the bundle conflicts internally, the rendered prototype and changelog override README summary prose.

> **Scope stance.** Same as Phases 2–3: routes, models, controllers and Turbo targets don't change unless a workstream flags otherwise. Shipped exceptions are the WS2 mark-as-read endpoint and WS6 personal-invitations route/controller; WS5 changes panel frame markup/JS. Parked WS3a schema and WS6a controller changes stay excluded until their owner gates are resolved. Behavior rebuilds get tests first.

## Progress (2026-08-19)

- **WS1 — shipped** (commit `a5d3ce4`). Popover primitive built on the native `[popover]` top layer (a `position:fixed` layer breaks inside the transcript's `contain: layout` root); message ⋯ and boost-only menus migrated off the scrim dialog; quick profile anchored at 320. Right-click-open defers past the gesture — opening mid-right-click let light dismiss read the trailing pointerup as an outside press. Verified: 9 message-row + 21 adjacent system tests, full unit suite.
- **WS2 — shipped** (commits `3d37a5c` endpoint, `2871b29` row menu, `01d9a1e` filter/browse/width). `Rooms::ReadsController#create` (+`resource :read` route, 3 controller tests); the row ⋯ menu partial on the primitive with all five actions wired (star/involvement/read/clipboard/membership endpoints); star buttons retired from rows (roster-panel star untouched); `popover_menu_tag` helper extracted and retrofitted across all four menus; hover-reveal + rail CSS; stars broadcast test re-pinned to the menu markup; 6 new system tests. Inline Browse link removed (the ROOMS-header ⋯ entry remains); filter field removed (view, controller, CSS, its test file); sidebar 272px from ≥1280 (1440 step dropped). Verified: full unit suite (1950), sidebar walls + row-menu + message-row system tests.
- **WS3 — shipped** (commit `9569ca6`). Replaced the footer's separate profile, theme, and account controls with one native anchored profile flyout: Profile, Settings, Appearance, permission-gated Invitations, admin Community settings, and logout with existing push-subscription cleanup. The admin workspace-header gear remains per v2.1; WS3a presence controls remain deferred. The flyout repositions while open on viewport changes, scrolls in short viewports, and is covered across desktop, rail, drawer, resize, and short-height system paths. Verified: 47 focused controller/system tests (253 assertions), CSS build, and RuboCop.
- **WS4 — shipped** (commits `ba31df1`, `959c430`). Mention wash now uses the 9% light / 18% dark tokens with the “mentioned you” meta label; pin labels state their consequence; `--color-link` and `--control-border` are corrected. The explicit owner decision keeps mention wash off date separators.
- **WS5 — shipped** (commit `7f0db16`). Room info is a 288px inline panel at 1160px; threads become a 360px inline panel at 1232px. Below each threshold, panels use a fixed right overlay with a 16% scrim; threads fill the phone column below 500px. Neither opens by default, forum posts retain their wider reading column, and Turbo navigation clears pending panel state. Verified: focused system tests (3 runs, 24 assertions), CSS build, JavaScript syntax, and RuboCop.
- **WS6 — shipped** (commit `91c51e4`). Settings panes reflect their real controller parameters; member invitations use an intentional personal-invitations route/controller; badges, bots, account identity, profile links/password, and the Members pane are covered by focused tests. The self-hosted suite, browser tests, CSS build, and RuboCop passed. The SaaS suite remains blocked by pre-existing tenant schema drift (`accounts.custom_styles` missing).
- **WS7 — removed from scope** (reverted in `7085d5d`). The rendered header has only the type glyph, name, member pill, topic, bell, and info toggle; privacy words belong in Browse and room creation, not the live room header.
- **WS8 — existing artifacts verified** (commit `73d6d99`). `public/offline.html` and its service-worker fallback already implement the offline state; `Authorization#render_forbidden` already serves the styled human-navigation 403. Only the bounded authorization-routing audit below remains.
- **Incidental fixes surfaced by the new tests** (call out in the eventual PR): `rooms_list` `read()` now removes the server-rendered `.notification-badge` span — classes only drive the dot, so a read row kept a stale count until its next re-render (pre-existing; visible once mark-as-read let you read a room while still looking at the sidebar). The shared system-test `visit` retry now also tolerates `ExpectationNotMet` from turbo-rails' in-visit stream await (same node-churn race `join_room` already tolerated).
- **Known residual:** the row-menu system tests flake roughly 1-in-6 under repeated back-to-back runs (load-correlated JS-boot/socket races, same family as the suite's known flaky set); stable in single runs.

## Already satisfied — no work, verify only

Claims v2.1 makes that `redesign-v2` already meets (the designer audited `main`):

- **Single pin per room** — `rooms.pinned_message_id`, replace-on-set, staff-gated, strip under the header, pin/unpin in the message `⋯`. Shipped 2026-08-18; consequence-stating menu labels shipped in WS4.
- **DM create flow** — sidebar picker (`.directs--new` frame swap), provisional compose surface, redirect-to-existing, lazy materialization with blank-first-send rollback, plus a rail compose entry. v2.1's "the `+` went nowhere" is stale. The picker already renders avatar pills + a filter dropdown (`_user_select` / `_template`), so gate #6's "pill picker reskin" is satisfied; only the sidebar-vs-pane placement remains a recorded divergence.
- **Group DMs** — all four surfaces branch on `many?`: avatar stacks, joined names, presence-dot suppression, member-count pill in the room nav. **Correction:** the participants panel (`directs#edit` + `_participants`) renders only a read-only avatar+name roster — it is missing v2.1's per-card presence, the member-set-identity copy, "Start one with more people", and "Leave", and the live group header has no dedicated "N people" pill entry point. That delta is **WS9**, not "verify only". Separately, the sidebar row abbreviates names — first-name-only for 1:1, "ER+JW"-style initials for groups (`_direct.html.erb:36,38`) — instead of the readable names the v2.1 comp uses (and that Slack and Mattermost both use: full name for 1:1, comma-joined member names for groups). That's **WS11**.
- **Browse rooms in a `⋯` on the ROOMS header**, left of the `+` — shipped (the menu also carries more than v2.1 draws; kept). Only the inline "Browse all rooms →" removal remains (WS2).
- **Composer** — Lexxy bar curated to B/I/S/`</>`, typing indicator floats above the card, Send accent-only while drafting. No `#` button exists to remove.
- **Message actions on `:focus-within`** and **5-minute same-author grouping** — both shipped. Grouping stays client-side (`message_formatter.js`), a recorded Phase 3 owner call; v2.1's ask for a server-side decision is a recorded divergence, not re-litigated.
- **Quick profile is already an anchored popover** (`popup_controller` + lazy turbo-frame). WS1 aligns its flip/clamp behavior, nothing structural.
- **Sidebar shell breakpoints** — the repository uses a 60px rail ≥834 and drawer <834, click-to-expand, scrim + scroll lock. v2.1 depicts a phone drawer below 500; retain the broader repository drawer as a recorded divergence unless its owner chooses to realign it.
- **Token consolidation (v2.1 build-order step 1) is a no-op.** `--lch-*` literals live only in `colors.css`; `@theme inline` references them (re-exposure for Tailwind, by design); no shadcn aliases exist. WS4 completed the `--color-link` and `--control-border` cleanups.

## Recorded decisions and pending gates

1. **Huddles: deferred, not cut.** v2.1's "cut, do not leave space" is adopted for redesign scope (nothing huddle-shaped exists on the branch to remove; the header "slot" is the `navbar-actions` layout area). The product track (LiveKit, requirements 2026-08-15) stays alive and gets its own design pass when built.
2. **Members IA: settings-shell pane, per v2.1.** Phase 3 WS8's standalone page is redone as an 880px pane inside the settings shell, rail visible with Members highlighted; every entry point (settings rail, header member pill, profile flyout) routes there. (WS6)
3. **Sidebar filter field: dropped, per v2.1.** ⌘K covers it; vertical space reclaimed. (WS2)
4. **Right-panel default-open: dropped, per v2.1.** No roster auto-open at ≥1280; neither panel ever opens by default. (WS5)
5. **Composer search button: kept — recorded divergence.** It is a live palette entry, not a dead affordance, and touch devices have no ⌘K.
6. **DM picker placement: shipped placement kept — recorded divergence.** Sidebar-inline + rail compose stay; the pane visuals (pill picker) apply as a reskin. v2.1 itself flags its pane placement as a deviation from the repo.
7. **Presence picker in the profile flyout (WS3a).** Pending owner verification. The choice is whether DND only decorates presence or also gates push; WS3 ships without it.
8. **Notification `mode` enum (WS6a).** Pending owner verification. `user_notification_settings.mode` (`nothing` / `mentions_and_dms` / `all`) exists but is unexposed; its visible precedence must be decided before the controller permits it.
9. **Optional group-DM custom naming (WS11a).** Pending owner verification. The v2.1 prototype fixtures a group named "print crew" — Slack-style *optional* group-DM naming (Slack lets you set a custom label that falls back to member names). Mattermost does *not* name groups (`sort().join(', ')` of member names), and this changelog says a conversation *is* its member set (`members_hash`, no in-place editing). WS11 ships readable joined member names with **no schema**; a real custom name is a nullable `name` column on group `Rooms::Direct` + a rename affordance + a member-name fallback, and would also want a group size cap (Slack 9 / Mattermost 8). Decide intent before building — it contradicts the member-set-identity framing, so don't infer it from the one fixture.

---

## WS1 — One anchored-popover primitive (build first; v2.1 build-order step 3)

Two primitives coexist today: `popup_controller` (`<details>`-anchored, flips near the viewport bottom — section-header `⋯`, quick profile) and `dialog_controller` (centered `scrim-dialog` over a dimmed backdrop — message `⋯`, emoji picker, ⌘K palette, new-room). v2.1 mandates the three *menus* (row `⋯`, message `⋯`, quick profile) be anchored dropdowns with shared behavior: hover/right-click open, trigger stays lit while open, flip when the menu won't fit below, clamp 12px inside every viewport edge, no dim layer, outside click and right-click close.

- Extend `popup_controller` into that contract (clamp, right-click, lit-trigger state, fixed-layer positioning so a scroll container can't clip it).
- **Migrate the message `⋯` from `scrim-dialog` to the primitive** — contents unchanged (reaction, reply, quote, edit, delete, copy link, bookmark, pin, mark unread), right-aligned to the trigger.
- Quick profile adopts the same flip/clamp path.
- The scrim-dialog stays for genuinely modal surfaces (palette, emoji, new-room) — v2.1 doesn't touch those.
- **Tests first:** menu opens on click and right-click, closes on outside click/ESC, flips at the bottom of the viewport, trigger reflects open state.

## WS2 — Sidebar: row `⋯` menu, star retirement, small deltas

The headline v2.1 sidebar change. Today: an always-visible star per row, no per-room context menu.

- **Hover-revealed `⋯` on room and DM rows; right-click on the row opens the same menu** (WS1 primitive, fixed-layer so the sidebar scroll container can't clip it). Items → existing endpoints:
  - Add to favorites / Remove from favorites → `room_star_path` (create/destroy) — the star button's plumbing, re-homed. The star *moves* into the menu; the feature is unchanged: starred rooms keep grouping under the existing FAVORITES section, which stays the visible state.
  - Mute / Unmute → `resource :involvement` update (the `from_sidebar:` helper variant already exists unused). The row's muted-bell indicator already renders.
  - Mark as read → **flagged: new endpoint.** `Membership#read` / `advance_cursor_to_head` exist as model API but nothing exposes them over HTTP (reading happens on room visit; `messages/unreads#create` is mark-*unread*). Add `resource :read, only: :create` in the room scope → thin `Rooms::ReadsController` calling the model. Clears the badge and drops the room out of UNREAD.
  - Copy link → client-side.
  - Leave room → `rooms/memberships#destroy` (existing `LastVisibleMemberError` handling).
- **The star button leaves the row** — favoriting lives in the menu now (moved, not removed; FAVORITES grouping is the state, the menu is the action). The roster-panel star toggle is untouched.
- Remove the inline "Browse all rooms →" list row; the ROOMS-header `⋯` entry remains.
- **Width: 272px from ≥1280** (today 240@1280 / 272@1440) — one media-query change.
- Filter field per owner gate #3.
- **Tests first:** menu actions hit their endpoints (favorite, mute, mark-read, leave); mark-read clears the unread badge; keyboard access to the row menu.

## WS3 — Sidebar footer: profile flyout

Today three separate controls (profile link, theme toggle, gear). v2.1: the avatar/name/email row is the single trigger for a flyout — Profile, Settings, Appearance (theme control moves inside), Invitations (only when `allow_users_to_create_invite_links` or admin), Community settings (admin), Log out. Presence picker per owner gate #7 (recommend omit).

- Built on the WS1 primitive, flipping upward (footer sits at the viewport bottom).
- The workspace-header gear stays or goes per the redlines — check at build time, don't leave two gears.
- **Tests first:** flyout renders role-appropriate items (member vs admin vs invite-permission-off), log out works.

### WS3a — Presence picker (parked: owner gate #7, verify before building)

The flyout's Available / Away / Do not disturb picker, built for real rather than as the prototype's non-propagating control:

- **Flagged: schema change** — a user presence-preference column (e.g. `users.presence_preference` enum `available` / `away` / `do_not_disturb`; name checked at build time against the connected-presence vocabulary so the two signals don't blur). Today presence is purely connection-derived (AnyCable broker / `connected_at`); this adds a declared override on top.
- Rendering: sets the dot on the footer row and the status line under the name (v2.1), and — beyond what the prototype wired — propagates to the roster, member directory rows, and DM presence dots, which read the combined signal (declared override wins over connection state; DND should also gate push, which touches the notification path — scope that explicitly when verifying).
- Live: broadcast on change like other membership/roster updates.
- **Do not start until the owner verifies scope** — the DND-gates-push question decides whether this is a small feature or a medium one.

## WS4 — Message row + pin labels + token nits (shipped)

- Mention wash uses `--color-message-mentioned` at 9% light / 18% dark, with the “mentioned you” meta label. The `.message--mentioned-unread` wiggle stays as a recorded divergence. The explicit owner decision excludes date separators from the wash.
- Pin menu labels now state the consequence: “Pin to room”, “Pin instead of current”, and “Unpin from room”.
- `--color-link` now follows `--color-accent-brand`, and `--control-border` is exposed to `@theme`.

## WS5 — Right panels: info/thread split (flagged; owner gate #4)

Today one panel element serves both roster and thread: 360px, inline ≥1024, full-screen bottom-sheet overlay below, roster auto-open ≥1280. v2.1 splits them:

- **Info panel 288px, inline ≥1160. Thread panel 360px, inline ≥1232.** The thresholds are arithmetic (272 sidebar + ~600px minimum transcript measure + panel width), so there's a deliberate band (1160–1232) where info is inline but a thread overlays.
- From 500px up to its inline threshold a panel becomes a **fixed right overlay** — left-edge shadow, 16% scrim over the transcript, scrim click closes — not today's full-screen sheet. The transcript keeps its full width. Below 500px, the thread takes the full column and the room becomes a back link.
- The forum-post panel keeps its wider clamp (post-as-panel is a recorded Phase 2 owner call).
- One arithmetic caveat v2.1 misses: below 1280 our sidebar is a 60px rail, not 272 — the fixed 1160/1232 breakpoints are *conservative* there (more room than the math assumes), which is fine; keep the designed numbers.
- Auto-open behavior per owner gate #4.
- **Flagged:** this touches the panel frame markup/JS (`thread_panel_controller`), not routes or streams.
- **Tests first:** thread inline at ≥1232; info inline/thread overlay from 1160–1231; overlays from 500–1159; full-column thread below 500; scrim-close in overlay mode; and open-panel resize across both thresholds without a stale scrim or inaccessible close control.

## WS6 — Settings panes to match their controllers (shipped)

The v2.1 settings audit, corrected by the verification sweep:

- **Notifications** — rebuild the pane on the four real params (`push_enabled`, `missed_email_enabled`, `email_frequency` hourly/daily revealed only when missed-email is on, `weekly_digest_subscribed`; root key `user_notification_settings`) plus the per-room involvement list from `ordered_memberships_for_notification_preferences` (bucket order starred → everything → mentions → muted, alphabetical within). **Copy correction:** the row cycle and labels follow the code — *Mentions only → All notifications → Notifications muted* (`SHARED_INVOLVEMENT_ORDER`), two-state for DMs — not the changelog's "All messages → Mentions only → Muted". `mode` per owner gate #8.
- **Identity** — admin: community Name, logo, and the two account-level email switches (`email_notifications_enabled`, `weekly_digest_enabled`), all in `account_params`. Member: read-only variant (`accounts#show` is ungated; only edit/update sit behind `ensure_can_administer`), stating that only administrators can change it. No Description anywhere — no column backs it.
- **Badges** — add the `icon` input (permitted; ≤50 chars; color strictly `#RRGGBB`) and render the icon with the chip on every surface it appears (list, role menu, roster, message meta, profile, hover card) from one definition source.
- **Bots** — display each bot's `webhook_url` (third permitted attribute).
- **Invitations** — member-facing page gated on `allow_users_to_create_invite_links` (default on; admins always pass). Copy should reflect that turning the setting off retroactively invalidates existing personal links (`invalidate_personal_invite_links`).
- **Account & data** — QR session transfer stays (`Sessions::TransfersController`). No export row in the self-hosted app — correct, **but only there**: the SaaS engine has a real workspace export (`saas/.../exports_controller.rb`); its settings surface is untouched by this phase.
- **Profile form** — add the Links group (`twitter_url`, `linkedin_url`, `personal_url` — already permitted, partially already in the form) and the **optional password field** (permitted but currently has no input; min 8, validated only when present). **Copy correction:** "a handle is enough" applies to X and LinkedIn only — `normalize_social_urls` never touches `personal_url`, so Website asks for a full address (or extend normalization; decide at build time, don't ship the wrong helper text). Email keeps the confirmation note (`handle_email_change`; hidden under SaaS, where email change is disabled). This item is the edit *form* only; the profile *card* affordances v2.1 §Profile ¶1 also asks for (own-profile "Edit profile" button) are unshipped — **WS10**.
- **Members pane** per owner gate #2.
- **Tests:** form round-trips for each pane; member-vs-admin rendering; SaaS suite at this boundary (`unset UNTENANTED_DATABASE_URL; SAAS=true bin/rails test saas/test/`).

### WS6a — Expose the notification `mode` override (parked: owner gate #8, verify before building)

Surface the orphaned global override in the Notifications pane:

- **Flagged: controller change** — permit `:mode` in `Users::NotificationSettingsController` (currently unpermitted, so no UI can set it).
- Control: a three-option choice above the per-room list — labels drawn from what `effective_involvement` actually does (e.g. Everything / Mentions & direct messages / Nothing), copy making clear it caps per-room settings rather than replacing them.
- The per-room rows should reflect the cap when it bites (a room set to All notifications under a `mentions_and_dms` override effectively delivers mentions only) — otherwise the pane shows a state the app won't honor.
- **Do not start until the owner verifies** — the interaction between the override and per-room rows is the design question to settle first (v2.1's pane doesn't know this enum exists, so there's no comp for it).

## WS8 — States: verify existing rendering

Do not build another offline or 403 page. Offline is a static, precached `public/offline.html`; navigated HTML GETs already have the styled `render_forbidden` path. Audit which member-reachable administrator URLs should render that existing page with a settings back-link, while preserving bare 403 responses for mutations, Turbo frames, and API clients. Tests should cover a stale community-settings GET and an installed-worker offline navigation.

- **Composer read-only / blocked states** — deferred to states work. The current `_composer_not_allowed` uses a red error line (DM-block only). The v2.1 “muted sunk card” treatment implies read-only variants (archived, banned) that may not exist as model/route coverage yet; settle coverage in this workstream rather than the visual-consistency sweep.

## WS9 — Group-DM participants panel + header entry (flagged: no schema or routes)

The one DM delta the Phase-3 "already satisfied" bucketing under-counted. The create flow, sidebar rows, provisional surface, group avatar stacks, and presence-dot suppression are genuinely shipped (verified: the picker renders avatar pills via `_user_select` / `_template`; `_direct` and both nav headers branch on `many?`), and the picker's sidebar placement stays per gate #6. What's missing is confined to the group-DM **participants panel** and its **header entry point** (v2.1 Participants-panel section; the rendered prototype is authoritative):

- **Participants panel** (`rooms/directs/_participants.html.erb`, rendered via `directs#edit`). Today: bare avatar+name cards. Add, matching v2.1:
  - **Presence** on each roster card — `directs#edit` sets only `@users`; thread the per-member status the header and sidebar already derive (`direct_member_status`) so the panel reads the same signal, not a second one.
  - **Member-set-identity copy** — a line stating a conversation *is* its member set (`members_hash`), so people can't be added or removed in place.
  - **"Start one with more people"** → `new_rooms_direct_path(user_ids: <current members>)` — the provisional compose pre-seeded with the current group. The controller already accepts `user_ids[]`; picking a different set opens a *separate* conversation and leaves this one intact (the singleton rule in `directs#new` does the rest).
  - **"Leave"** → `rooms/directs#destroy` (existing action; group leave).
- **Live group header** (`rooms/show/_nav.html.erb`). Today the 1:1 case shows "View profile"; a group shows a static "N members" subline and no actions-row affordance — the panel is only reachable by clicking the name. Add a **"N people" pill** in `navbar-actions` for `dm_members.many?`, in place of View profile, linking to `edit_room_path(room)`. Resolve the name-link-vs-pill double entry point at build — one authoritative affordance.
- **Out of scope / recorded divergences:** no add-participant route (`resources :directs` has none — v2.1 agrees); picker placement (gate #6); the 1:1 DM edit path is unchanged.
- **Tests first:** the group participants panel renders per-card presence and both actions; "Start one with more people" pre-seeds the provisional compose with the current members; "Leave" routes to `directs#destroy`; the group header renders the "N people" pill while a 1:1 keeps "View profile".

## WS10 — Own-profile card: "Edit profile" affordance (flagged: view-only, no schema or routes)

The profile-card half of v2.1 §Profile (¶1) — distinct from WS6's shipped edit-*form* work (¶2). v2.1: on your own profile the Message / Block buttons are replaced with a labeled **"Edit profile"** that opens Settings → Profile, and the name shows instead of "You". Branch state:

- **Name-not-"You"** — already satisfied; both surfaces render `user.name` (`users/show.html.erb`, `_quick_profile.html.erb`). No work.
- **Full profile page** (`users/show.html.erb`). Today the self-edit affordance is a pencil *icon* in the nav (`:10`), not a labeled button in the hero actions row; Message is already gated out (can't DM self) and Block is hidden on self (`:85`). Add the labeled **"Edit profile"** button to the actions row (→ `user_profile_path`); decide at build whether it supersedes the nav pencil or both stay. "All messages" (`:84`) stays.
- **Quick-profile popover** (`_quick_profile.html.erb`). Today the self case shows only "View profile" and no edit affordance (`:60`). Add "Edit profile" for `user == Current.user`.
- **Out of scope:** no change to other users' cards (Message / Direct message / Block / All messages render as today).
- **Tests first:** the own profile page and own quick-profile card render "Edit profile" (→ profile settings) with no Message / Block; another user's profile is unchanged.

## WS11 — Sidebar DM row: readable names (flagged: view-only, no schema or routes)

The sidebar DM row rolls its own name abbreviation instead of the app's `display_name`, producing labels neither the v2.1 comp nor the prior art uses. Prior art (both checked): **Slack** shows the full display name for 1:1s and comma-joined member names for groups; **Mattermost**'s group name is `sort().join(', ')` of member display names (`mattermost-redux/.../channel_utils.ts:138`). The current row (`app/views/users/sidebars/rooms/_direct.html.erb`) instead shows first-name-only for 1:1 (`:38`) and plus-joined initials ("ER+JW") for groups (`:36`).

- **1:1 DM** → the other member's **full name**, matching the live header, which already uses `room_display_name` → `Room#display_name` (`app/models/room.rb:379`).
- **Group DM** → **comma-joined member first names** (Slack-style; full names overflow the 272px rail), e.g. "Iris, Marcus", with ellipsis truncation, replacing the initials. Presence-dot suppression for groups stays.
- Route the sidebar through `display_name` / a shared helper so the sidebar, live header, and composer placeholder can't drift.
- **Out of scope:** custom group-DM naming (gate #9 / WS11a); avatar sizing and row density (measure against the redlines at build — the comp reads more compact than the current stack).
- **Tests first:** a 1:1 row renders the full name (not first-name-only); a group row renders joined member names (not initials); truncation keeps the row single-line at 272px.

---

## Sequencing & commit boundaries

1. **WS1–WS4 and WS6** — shipped; retain their records for verification history.
2. **WS5 panel split** — shipped in `7f0db16`.
3. **WS8 authorization-routing audit** — next; narrow verification only, no new state pages.
4. **WS9 group-DM participants panel + header pill** — next; view/controller-local, no schema or routes (reuses `directs#new`'s `user_ids[]` pre-seed and the existing `directs#destroy`).
5. **WS10 own-profile "Edit profile" affordance** — next; view-only, no schema or routes.
6. **WS11 sidebar DM readable names** — next; view-only, no schema or routes (reuses `Room#display_name`).
7. **WS3a presence picker · WS6a `mode` exposure · WS11a group-DM custom naming** — parked; each starts only after the owner verifies its gate (#7, #8, #9). None block the shipped work or WS5.

Each workstream = one commit or a small bisectable series on `redesign-v2` (still unpushed; push/PR only on explicit approval).

## Verification

- Tests-first for every behavior change (row-menu actions, mark-as-read, panel thresholds, settings forms); targeted system walls matched to each change, not the full sweep.
- Light + dark screenshots of touched surfaces; drawer/rail/desktop widths for WS2, WS3, WS5.
- Designer-boundary check: no schema changes; shipped HTTP additions are WS2’s `Rooms::ReadsController#create` and WS6’s personal-invitations route/controller. WS5 changes only panel markup/JS.
- Treat rendered v2.1 prototypes and `CHANGELOG-v2.1.md` as authoritative when they conflict with README summary prose.
- Record the SaaS suite’s tenant-schema prerequisite separately; do not imply it passed as WS6 verification.

## Appendix — v2.1 claims corrected by the 2026-08-19 verification sweep

Recorded so the handoff isn't re-trusted on these points later:

- **"v2 treated every conversation as one-to-one" / "the `+` went nowhere"** — true of the comp, false of the branch: group DMs and the full DM create flow shipped in Phase 3.
- **"No mention autocomplete behind the `@`"** — false on the branch: Lexxy mention prompt is live (`mention_prompt_tag`, `application/vnd.sabha.mention`). The `@` button stays.
- **Composer search icon "promises nothing"** — false: it opens the ⌘K palette (gate #5).
- **"No export controller exists"** — true self-hosted, false in SaaS (`saas/.../exports_controller.rb`).
- **Involvement cycle/labels** — code says Mentions only → All notifications → Muted; "All messages" isn't the app's vocabulary.
- **`account_params`** also permits `:logo` + nested `settings` (incl. `accent`); the changelog's list was incomplete but nothing in the design conflicts.
- **`can_administer?(record)`** also grants the record's creator — fine for community settings (no record), matters for room delete.
- **Mention wash values** — WS4 now uses the token spec’s 9%/18% values. The explicit owner decision excludes date separators from the wash.
- **`normalize_social_urls`** covers X + LinkedIn only, not `personal_url`.
- **`password`** is permitted but has no form field — the design's Password field is a small build, not a reskin.
- **Pinning scope** — `pinnable?` is `!direct? && !sub_room?`; matches the design showing the strip on rooms only.
- **Token duplication** — already consolidated on the branch; v2.1 build-order step 1 is a no-op beyond two one-line nits.
- **Notification `mode` enum** — exists, has real effect, unexposed anywhere; unknown to the design (gate #8).
