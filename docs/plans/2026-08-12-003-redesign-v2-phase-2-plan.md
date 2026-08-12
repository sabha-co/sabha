# Plan: Sabha v2 redesign — Phase 2 (reskin + rebuild to handoff fidelity)

**Status:** complete except the composer emoji button (awaits Lexxy) — WS0–WS6 built through 2026-08-13, incl. the owner-requested follow-ups (footer theme toggle, move-search, message-menu dialog, phone polish) · **Date:** 2026-08-12 · **Builds on:** Phase 1 (`redesign-v2`, Steps 1–6, unpushed) · **Source of truth:** `~/dev/design_handoff_sabha_v2` (design references, not code)

> **What this is.** Phase 1 completed the designer's six-step build order **as a reskin** (plus sanctioned rebuilds: the shell/sidebar move, message-row scale, action bar, composer typing row, accent system, forums data section) and the token system was verified pixel-matching the spec. What the reskin discipline deferred is a **concrete, enumerable set** — the typeface, a handful of DOM/Stimulus rebuilds, responsive breakpoint work, and a cluster of data-shaped UX the designer's own scope ("routes/models/controllers/Turbo targets don't change — the DOM inside them does") parked. Phase 2 closes that gap so the running app matches the handoff's **look and interaction**, not just its tokens.

> **Scope (owner call, 2026-08-12): ①②③ + data-driven ④.** In: the type system; responsive completion; the contextual right-panel; **a reactions reskin** (visual only — the aggregated/optimistic rebuild is deferred); v2 scrim dialogs; the inbox/activity **data** surfaces; loading skeletons; the live connection banner + message Retry; the six-box OTP input; auth polish. **Not** in: net-new features.

## Confirmed directions (owner call, 2026-08-12)

| # | Fork | Decision | Effect |
|---|---|---|---|
| **P2-1** | **Scope depth** — visual-only vs. + data/behavior vs. + features | **+ data-driven UX (④ minus features)** | Adds Activity verb rows, Threads-inbox cards, connection banner, and Retry on top of the visual/DOM rebuilds. Reactions are reskinned only (they work today). Net-new features stay out. |
| **P2-2** | **Composer format bar** — the persistent B/I/S/`</>`\|@/# bar is entangled with the parked Trix→Lexxy migration | **Defer to Lexxy** | The always-visible format bar waits for the Lexxy migration; the rest of the composer polish (emoji button, search-in-tools) ships now. |
| **P2-3** | **Reaction chips** — per-user (today) vs handoff's aggregated | **Reskin only; defer the rebuild** (owner call, 2026-08-12) | Reactions work today, so Phase 2 only moves the chip styling closer to the handoff. True one-chip-per-emoji aggregation + optimistic behavior (a boost render/broadcast change) is deferred to a future functional pass. |

Standing from Phase 1: message **grouping stays client-side** (C3); **compact density** deferred (C5); **Huddle** out (net-new); accents already shipped (C1).

> **Path note.** Bare CSS names → `app/assets/stylesheets/application/*.css`; `application.css` (Tailwind entry) → `app/javascript/entrypoints/application.css`; JS → `app/javascript/{models,controllers}/*.js`; view paths given in full.

## Standing constraints

Single-line commits, no attribution; **nothing pushed / no PRs without explicit approval**; behavior rebuilds get tests **first** (tests-before-refactor); run **both** suites each step (`bin/rails test` + `SAAS=true bin/rails test saas/test/`, unset `UNTENANTED_DATABASE_URL` first); SaaS + Hotwire-Native (`native.css`) parity each step.

**System tests — run the specific file for the changed surface, never the full sweep.** The whole `test:system` run takes ~100s and carries pre-existing flakes (the `SendingMessages#join_room` ObsoleteNode races), so running it every iteration stalls progress. For a UI change, run only the matching file(s) — `bin/rails test test/system/<file>.rb` (note: `bin/rails test`, not `test:system`, so file args are honored) — matched to the surface touched.

---

## Build status (2026-08-12)

WS0, WS1, WS2, WS4 and WS6 are **built** on `redesign-v2`; WS3 and WS5 are **partly built** (the clean pieces done, the rest flagged below). WS2 was scoped by the owner to the contextual-panel core + room roster (profile-in-rail declined). Every behavior rebuild landed tests-first; both suites stay green. The workstream sections below keep the original plan text — where implementation diverged, the divergence is recorded here.

| WS | Status | Commits | Notes |
|----|--------|---------|-------|
| **WS0** Type | ✅ Built | `cf3eeab` | Instrument Sans **roman + italic** (real italics) + JetBrains Mono, variable wght 400–700, self-hosted with OFL licenses; all four mono sites → `--font-mono`; preload on both the app and session layouts. |
| **WS1** Responsive | ✅ Built | `583c5b6` `81ead12` `9df1364` `2cafd2e` | See deviations below. |
| **WS6** Auth | ✅ Built | `629c78b` `4c3cb31` `f35adc2` | Six-box OTP mirrors `OtpCode.sanitize`; in-card alerts across 5 session-layout views; "Send another" resend. Expired view — see deviation. |
| **WS2** Panel | ✅ Built | `99a0084` `e51aee1` `037c6cf` `8d1dc5c` | Right column is a fixed 360px contextual rail (`99a0084`), widening to the 680 reading column only for forum posts (`:has(.forum-post-header)` — carries WS1's readW). Room presence roster (`e51aee1`) opens in the panel from the header member count; verified against the room-info redlines and aligned (`037c6cf` `8d1dc5c`): dimmed away rows, favourite/settings button pair. Profile-in-rail declined by owner — see deviation. |
| **WS3** Reactions | ◐ Partial | `28ed6f9` `3015d05` | Reactions reskin was **already done in Phase 1**; **scrim dialogs built 2026-08-13** (reaction picker + role menu on a new native-`<dialog>` primitive). The composer emoji button and move-search remain flagged — see WS3 notes below. |
| **WS4** Inbox data | ✅ Built | `5802bce` `4c2bdbf` `7ce62aa` | Activity verb rows, four filter tabs, Threads-inbox cards with inline follow. See deviations below. |
| **WS5** States | ◐ Partial | `11bd15f` `2e5259f` | Live connection-lost banner and sidebar cold-start skeleton built. Message Retry and the remaining skeletons are flagged — see WS5 notes below. |

**WS1 deviations from the plan text:**
- **`120ch` → `1024px`, uniformly (not "1024/1280").** Instrument Sans makes `120ch` resolve to ~1279px (vs ~1024 in the old system font), so the WS0 font swap had shifted every content breakpoint ~250px. All 36 sites map to **1024px** — restoring pre-WS0 behavior and matching the handoff's "tablet landscape" breakpoint. The dock stays at the existing px `1280`.
- **Header-drops are moot.** The current room header (`rooms/show/_nav`) has no member-pill, topic line, or standalone bell — those are handoff elements the app hasn't built. Not fabricated (building them = net-new).
- **Mini-composer was mostly already built.** The format bar already sits behind `composer#toggleToolbar` — no new Stimulus controller needed. The only real gap, and the only change, was **44px phone tap targets** (`<500px`).
- **Reading column `680/560` moved to WS2.** It needs the 360px-thread-vs-wide-post split WS2 builds (a 680 column can't live in a 360 panel).
- **Deferred, small:** member role "collapse into row" (shared `rooms/threads/_user`); reply-button 40/28 tap target.
- **Built:** forum width-steps (`.forum-card__stack` faces `<1024`, `.forum-filter__sort` `<500`, post title 21px `<500`); rail rooms (first 4 of the main Rooms list as compact glyph rows in the 1024–1279 rail, reusing the live-updating rows via a `.rail-rooms` hook + `.room__glyph`/`.room__name` split).

**WS6 deviation — the expired-link view was not built.** Expired/invalid redirects to the code screen, where the in-card alert ("Invalid or expired token") + the "Send another" resend form a recovery loop. A dedicated view would need an expired-vs-invalid distinction (`AuthToken.lookup` returns `nil` for both) plus new routing — net-new, and a worse experience than the resend loop.

**WS4 deviations from the plan text:**
- **Boosts already had verb rows.** Only mentions and thread-replies rendered as raw message rows, so the verb-row swap targets just those two (glyph `@` / `↩` on a corner badge over the actor avatar). A reply's row keys to the *parent* room — its own room is the thread/post sub-room.
- **Four filter tabs, not three.** The comp's filter is All / Mentions / Replies / **Reactions** (Reactions == boosts); the plan text listed three. `Inbox::ActivityQuery` maps each tab value to an `activity_type`, and the filter rides through pagination via the paginator URL. Streaming is **not** filter-aware — a new off-filter notification can append until reload (a snapshot, not filter-aware streaming). The filter renders **in the nav bar** beside the title (`2f238ab`), not as an in-feed row — `#nav` is `position: fixed`, so an in-feed row's left tabs sat under it on desktop.
- **Thread cards are static-render, not live-rebuilt.** Each card shows room, "started by", an optional "N new" pill (one batched query, `Inbox::ThreadsQuery.unseen_reply_counts` — no N+1), the root message, the embedded `messages/threads` reply-count footer, and an inline follow toggle. The toggle reuses `rooms/threads/_follow_control`, so **thread Unfollow now exists in the app** — closing the sharpest thread↔forum gap. Reply count and last-reply update live (the embedded footer is the existing broadcast target); the **"N new" pill and follow state reflect page-load state**, and a brand-new thread arriving live still appends as a plain message row until reload — because the `inbox_threads` broadcast is viewer-less (the follow control needs `Current.user`). Fully-live cards would need a per-viewer `inbox_threads` broadcast rework — deferred, like the reactions pipeline. Cards are not fragment-cached (they carry per-viewer state). The empty-state hide check (`.message-area:has(.message)`) was taught about `.thread-card` (`2f238ab`) — cards omit the `.message` class, so without it "No threads yet" leaked over a populated list.

**WS3 (Reactions/dialogs/composer) — partial. What's built, what's flagged:**
- **Reactions reskin → already built in Phase 1.** `boosts.css` already carries the v2 look (23px pill, radius 999, 1px border, 17px reactor avatar, `boost--mine` accent tint via `boost_delete_controller`, trailing add affordance). The comp's only extra nuance — reactor avatars "overlapping −5" — is the *aggregated* one-chip-per-emoji look, which P2-3 deferred. So nothing to do; not churned.
- **Composer emoji button → flagged (net-new).** There is no emoji picker in the app (the reaction flow types an emoji into a text field, it isn't a grid). Adding a composer emoji button means building an emoji-picker component — a feature, not a reskin. Not built without owner sign-off.
- **Composer move-search → ✅ built (2026-08-13, owner ask).** Search moved from the standalone circle beside the composer into the tools row (attach → rich-text → search, per the comp's cluster; the comp's emoji slot stays empty pending Lexxy). `_composer_fields` gained an opt-in `search_path:` local (nil for thread/provisional composers); the `composer__context-btn` block and its width-gate CSS are gone; the view-transition into the search page is preserved.
- **Footer theme toggle → ✅ built (2026-08-13, owner ask — was flagged during the footer-chip rebuild).** Sun/moon button in the footer chip row; `theme_controller#toggle` flips the *effective* appearance to an explicit light/dark choice (the profile page's three-state control remains the way back to System). Icon state is pure CSS keyed off `:root` theme scoping. System-tested.
- **Phone polish (2026-08-13):** thread-panel header swaps the thread glyph for `#` below 1024 (the panel is the room context full-screen); meta-row message actions get 40px tap targets on coarse pointers. The WS1 "member role-control collapse on phones" item is **moot** — the manage-member dialog consolidation reduced the row to one Manage chip, which fits at 390px.
- **Scrim dialogs → ✅ built (2026-08-13, `28ed6f9` reaction picker, `3015d05` role menu).** New primitive: `dialog_controller.js` on a native `<dialog>` (showModal gives the focus trap/Esc/focus-return for free; the controller adds scrim-click close, open-on-`turbo:frame-load`, close-on-successful-submit) + `.scrim-dialog` CSS to the redline contract (radius 16, scrim `rgba(12,14,20,0.36)`, `--shadow-overlay`; explicit `inset:0; margin:auto` because the global reset kills the UA centering). **Reaction picker:** all boost entry points now navigate a shared layout-mounted `reaction_picker` frame — full 7-column emoji grid + the custom 16-char input in one dialog; the ⋯ menu's inline emoji row became an "Add reaction" item; the old inline `boosts/new` input flow and `soft_keyboard_controller` are gone. `create.turbo_stream` targets unchanged (designer boundary held). **Role menu:** the members-page row controls (crown/shield toggles + badge select + inline Deactivate) consolidated into one "Manage" chip opening `accounts/users#edit` in a per-page dialog — role rows with tick + hints, badge chips, Deactivate + **Ban** actions (Ban surfaced from the profile page, per the comp). Reactivate/Unban stay inline (those users aren't `manageable_by?`). Tests-first: `boosting_messages_test` rewritten to the dialog contract + new `managing_members_test` (role change, badge, deactivate-with-confirm, esc). **Follow-up completed same day (owner ask):** the ⋯ message-options menu also converted to a scrim dialog — `dialog_controller` gained an optional `modal` target (trigger button beside the dialog in a wrapper) and menu semantics (any item click dismisses); the per-message `<details>`/popup flow, its arrowed-dropdown CSS, and the `popup` controller wiring on messages are gone; item links/forms, `turbo_confirm`, and frame targets unchanged; Delete row carries the negative tone. The `.message:has([open])` bar-reveal rule carries over to `dialog[open]` unchanged.

**WS5 (States) — partial. Built:**
- **Live connection-lost banner** (`11bd15f`) — `connection_status_controller` subscribes the (previously empty) `HeartbeatChannel` via the shared turbo-rails cable; when the socket drops every subscription is `disconnected()` together, so it's a faithful whole-connection signal. Shows the amber "Reconnecting — new messages will appear when the connection returns." strip (States-comp tones), hidden on reconnect. Mounted app-wide in `application.html.erb`. Render-tested (hidden by default + controller wiring); the live toggle is cable-driven, not unit-testable without a forced WS drop.
- **Sidebar cold-start skeleton** (`2e5259f`) — the lazy `user_sidebar` frame now renders four pulsing placeholder rows until its rooms land (via `sidebar_turbo_frame_tag`, so every surface gets it at once). Theme-agnostic bars (`--color-text` at low alpha), reduced-motion aware. The room first-paint skeleton has **no slot** (messages render server-side inline, per the plan); the older-messages spinner already exists (`message__loading-indicator`) and needs only a cosmetic reskin if wanted.

**WS5 Message Retry → ✅ built (2026-08-13, `84bcf2d` server, `4b04b91` client; owner approved the idempotency approach).** Server: unique index on `messages.client_message_id`; `messages#create` rescues `RecordNotUnique` and re-answers with the room's existing message (no re-broadcast) — a replayed send is the same message. Landing the index surfaced a real generator bug: the app minted ids with `Random.uuid`, which draws from the **seedable** Mersenne Twister — under the test runner's `srand` the sequence replays, and reused SaaS tenant DBs (which persist across tests) collided; switched the three app call sites to `SecureRandom.uuid`. Client: the composer stashes `{url, FormData}` with the messages controller before it resets; a failed `turbo:submit-end` now renders the States-comp chip on the dimmed draft ("Couldn't send. Your message is still here." + Retry); Retry re-POSTs the original payload with an `Accept: turbo-stream` fetch and renders the response — the create stream appends by `message_<client_message_id>` and Turbo appends dedupe by id, so the pending node swaps for the real message on either the response or the broadcast, with no duplicate possible. File-upload failures keep the chip without Retry (the File isn't retained); the pending payload is in-memory, so a reload drops the retry affordance (the draft node too — unchanged from before). Verified: idempotent-create controller tests, `message_retry_test` system tests (fetch-blip simulation), live browser check.

**Pre-existing bugs found while testing, fixed separately (not Phase 2 scope):**
- `25daea4` — the contrast sidebar footer had no visible bottom bar: under `data-contrast`, `--color-bg-sunk` collapses onto `--color-bg`, so the footer's sunk background vanished. Added a hairline.
- `2e8c9d8` — `Account#join_code` returned `nil` for fixture/seed-created accounts (the `after_create` backfill callback doesn't fire for those), crashing the About page's invite partial. `join_code` now self-heals by backfilling the global code.
- `84bcf2d` (folded into the Retry idempotency commit, which is what surfaced it) — the app minted `client_message_id`s with `Random.uuid`, which draws from Ruby's **seedable** Mersenne Twister rather than a CSPRNG. Any `srand` (the test runner does this) makes the "unique" id sequence replay — SaaS tenant DBs, which persist across test runs, collided the moment the unique index existed. All three app call sites (`Message#set_default_client_message_id`, `Room#post_system_message`, `Room#post_welcome_message`) now use `SecureRandom.uuid`.

---

## WS0 — Type system (foundation; lands first, like tokens did in Phase 1)

> **✅ Built** (`cf3eeab`). Shipped with roman + italic faces and all four mono sites repointed — see Build status.

**Why first:** flipping the face ripples to every surface; do it before per-component polish so nothing is sized twice.

- New `app/assets/fonts/` — self-hosted **Instrument Sans** variable woff2 (OFL; 400 body / 500–600 labels / 700 titles in one file). Optional **JetBrains Mono** woff2 for code.
- `base.css`: add `@font-face { font-display: swap; src: url("../fonts/…woff2") }` **here, not in the Tailwind entry** — Propshaft rewrites relative `url()` in vanilla CSS (proven by `icons.css`); the Tailwind-CLI entry resolves against the build dir instead. Flip the single `--font-family` line (`base.css:2`) → `"Instrument Sans", <existing system fallback>`, which re-faces the whole app. Optional `--font-mono` token repointing the 4 mono sites (`base.css:156`, `application.css:72-74`, `actiontext.css:180`, `auth.css:275`).
- `app/views/layouts/application.html.erb` head (~L34): `<link rel="preload" as="font" type="font/woff2" crossorigin>` to cut FOUT.
- Optional scale reconciliation: map the rem 6-level scale (`application.css:49-54`) onto the handoff px role scale (body 15/1.55, room-title 16/700, section-label 11/0.07em). Sizing is already token-driven, so the ripple is bounded; the family swap is the load-bearing change.
- Docs on merge: `CLAUDE.md:159` typography line; `docs/BRANDING.md`.
- **Risks:** FOUT (swap + preload; system fallback stays in the token so text paints immediately); confirm woff2 weight/axis coverage (no synthetic bolding); verify under `native.css` (`application.html.erb:37`) and that SaaS views inherit `--font-family`. Do **not** hotlink Google Fonts (privacy mandate, C4). **`ch` coupling (couples WS1):** `120ch` breakpoints resolve against the advance width of the `0` glyph, so swapping to Instrument Sans shifts the px-equivalent of every un-migrated `120ch` — WS0's font flip and WS1's `120ch`→px unification must land together or adjacent, not with WS1 far behind, or breakpoints move mid-redesign.
- **Verify:** light+dark screenshots across surfaces; no behavior tests.

## WS1 — Responsive completion (breakpoint unification, rail rows, mobile composer)

> **✅ Built.** Deviations from the text below are in Build status: breakpoints unified to `1024px` (not 1024/1280), header-drops moot, mini-composer = tap targets only, reading column → WS2.

The breakpoint machine is **split**: Phase 1 put the *sidebar* on pixel breakpoints but left thread/composer/content on the legacy `120ch`. Unify, then finish the per-width rules.

- **Migrate content panels off `120ch` → pixel breakpoints (1024/1280):** migrate **all ~40 `120ch` breakpoints**, not a sample — grep-verified across `layout.css` (incl. 82, 153), `thread_panel.css:15,26`, `composer.css:9`, `panels.css` (~16 occurrences — the file WS2's right-panel host lives in), `nav.css`, `messages.css`, `sidebar.css`, `embeds.css`, `dm_conversations.css`. Migrating only a subset turns the two-way split into a three-way split.
- **Header element drops (RESKIN, `display:none @media`):** member-pill + topic at 834, bell at 390, thread-card last-reply timestamp at 834. (The *pinned bar* the handoff draws needs a Pin model — out of scope; leave the slot.)
- **Post/forum/DM/members width steps (RESKIN):** reading column 680/560/full; forum sort-drop + participant-stack; member role-control collapse on phones.
- **Sidebar rail per-room rows (REBUILD):** the 1024–1279 rail shows tool icons only (`sidebar.css:59-61` hides `.rooms`); the handoff shows the first ~4 rooms as compact glyph rows with unread badges. New compact-row markup + rendering path in `app/views/users/sidebars/show.html.erb` + CSS. (Live-huddle dot = out.)
- **Phone mini-composer (REBUILD):** below ~500px, one-row composer, ≥44px targets, formatting behind `＋`. New Stimulus controller + markup; today only hides the context button at `120ch` (`composer.css:7-13`).
- **Tests-first:** rail per-room row rendering; mini-composer `＋` disclosure.

## WS2 — Contextual right-panel host (highest structural risk; own commit series)

> **✅ Built** (`99a0084` structural core, `e51aee1` room roster). Deviations from the text below, all deliberate:
> - **No new panel-host or "swap controller."** The existing `thread_panel_frame` + `thread-panel` Stimulus controller *are* the contextual host — thread, post, and now room all render into the same frame, so swapping is just frame navigation. The grid change is `--thread-width: 360px`, widened to `clamp(360px, 42vw, 680px)` only when the frame holds a post (`body:has(#thread-panel:not([hidden]) .forum-post-header)`). That single `:has()` rule is where WS1's reading column (`readW 680`) landed — no separate reading-width work.
> - **Room panel = presence roster, scoped by the owner to "roster only."** `Room::Roster` buckets the room's members into **here now** (the `connected` scope: refcount + fresh last-seen) and **away** (disconnected but seen within the away tier); offline is a count, not a section — matching the handoff, which shows only Here-now/Away. Note the model's own `activity_status` `:away` tier is effectively unreachable via `activity_statuses_for` (a `connected` member's last-seen is always fresh → `:active`), so the roster defines its buckets directly off the `connected`/`disconnected` scopes. `Rooms::RostersController#show` → `room_roster_path`; the header member count (`link_to_room_roster`, was `link_to_edit_room`) opens it, with a Settings link inside the panel back to full room settings.
> - **Profile-in-rail: declined by owner (2026-08-12).** The message-avatar quick-profile hovercard already works well and stays; only the room roster was in scope this pass.
> - **`<1024`:** the panel already goes full-screen overlay (existing behavior); the thread's parent-room "back link" already exists as `.thread-panel__room`. The thread-header glyph→`#` swap is a cosmetic detail left as a minor follow-up.
> - **Verified against the redlines (`037c6cf` `8d1dc5c`).** Compared the built roster to the handoff's room-info panel (exact inline styles) and reconciled: away rows dim to opacity 0.65 and drop their dot (the section header carries status); here-now names 13.5px/500, avatar 26px, dot 9px lifted above the overflow-clipped avatar figure with `z-index`. Added the mockup's **favourite + settings button pair** under the description (favourite = optimistic `star-toggle` Stimulus controller against the existing star endpoint, which only answers `head :ok`); dropped the header Settings chip, the member-count subtitle, and the "View all" footer. Two handoff conflicts resolved by owner call: panel width stays **360** unified (mockup draws room-info at 288 — README says 360) and the button pair was **added** (vs keeping Settings in the header). Light + dark screenshotted live.
> - **Verification:** `Room::Roster` categorization (5 tests) + `Rooms::RostersController` render/auth/favourite-guard (5 tests) + real-data runner check; unit + SaaS (305/0) green; light + dark live screenshots.

- Today only the **thread panel** occupies the right column, at `120ch`, 50/50 split (`layout.css:149-174`). The handoff wants a **single 360px contextual host ≥1280** that swaps **Thread ↔ Room ↔ Profile** (Huddle panel out; leave the slot).
- New panel-host markup + a Stimulus swap controller; grid change to a fixed 360px column. Below 1024: thread takes the full column, the room demotes to a **back link**, and the thread header glyph swaps to `#` (couples with WS1's breakpoint migration).
- **Room panel** content: categorized **here-now / away / offline** roster. `presence_controller.js` + `app/views/rooms/layouts/_members_panel.html.erb` exist, but the categorized roster is a **new query** (data ④). Degrade to the existing members panel if the roster query slips.
- **Profile panel:** swap-in the existing profile card.
- **Tests-first:** panel swap preserves Turbo frame/stream mechanics; the thread `<turbo-frame>` and stream targets must not change (designer boundary).

## WS3 — Reactions reskin, scrim dialogs, composer polish

> **◐ Partial.** Reactions reskin was already done in Phase 1 (no-op). Scrim dialogs, the composer emoji button, and move-search are flagged in Build status — net-new (emoji picker), a rebuild deserving its own tested pass (dialogs), or low-value/fiddly (move-search).

- **Reactions reskin (RESKIN — do not touch the pipeline):** reactions work today and stay as **per-user** chips; leave the boost pipeline untouched (`_boosts.html.erb`, `messages/boosts/_boost.html.erb`, `Boost#broadcast_create`/`broadcast_removal`, `create.turbo_stream.erb`). Move only the chip *styling* closer to the handoff — pill shape, ~17px booster avatar, accent tint on your own chip (the `boost--mine` class is already stamped by `boost_delete_controller`), and a trailing `＋` add affordance beside the row. **State plainly:** this keeps one chip per reactor (N reactors = N chips); true one-chip-per-emoji aggregation + optimistic insert is a boost render/broadcast rebuild and is **deferred** (see Out of scope).
- **Scrim dialogs (REBUILD):** convert the reaction picker + role menu from `<details>` popups (`_actions.html.erb:40-47`; role menu deferred in Phase 1) to the v2 dialog (radius 16, scrim `rgba(12,14,20,0.36)`, header/footer hairlines, `shadow-overlay`, scrim-closes). Changes Turbo/focus mechanics, not skin.
- **Composer polish (RESKIN):** add the emoji-picker button to the tools row; move Search **inside** the tools row (`app/views/rooms/show/_composer.html.erb:15-18`). **Format bar deferred to Lexxy (P2-2).**
- **Preserve** `message_formatter.js` client-side grouping + live re-thread on insert/delete.
- **Tests-first:** dialog open/close + keyboard. Reactions reskin is visual only (light+dark screenshots; the existing boost pipeline keeps its current tests).

## WS4 — Inbox / Activity data surfaces (④ query work)

> **✅ Built** (`5802bce` `4c2bdbf` `7ce62aa`). Verb rows for mentions/replies, four filter tabs (adds Reactions), and static-render Threads-inbox cards with inline follow — see Build status for the deviations, notably the viewer-less-broadcast limits on the cards' "N new" pill and follow state.

Both Activity and Threads inboxes render **raw message rows** via `search_results_tag` today (`app/views/inboxes/`).

- **Activity verb rows:** "X mentioned you in Y" + a kind glyph. Per-notification verb copy + a grouping/rendering query off the existing `Notification` model.
- **Threads-inbox thread cards:** grouped by thread — room, "started by", "N new" badge, root text, N replies, inline Unfollow. Grouping query by thread.
- **Activity filter tabs (All / Mentions / Replies):** new scopes/params + the existing `.segmented-control` pattern.
- **Tests:** query/scope coverage + the render.

## WS5 — States completion (loading + live failure)

> **◐ Partial.** Built: the live connection-lost banner (`11bd15f`) and the sidebar cold-start skeleton (`2e5259f`). Message Retry is flagged in Build status (needs a `client_message_id` idempotency decision); the room first-paint skeleton has no slot; the older-messages spinner already exists.

- **Loading skeletons (REBUILD):** sidebar cold-start (the sidebar is a lazy `turbo-frame` — real slot); older-messages spinner (**already exists** as `message__loading-indicator` / `.message--loading-up/down` — reskin to the handoff look); optimistic in-flight message at 55% opacity (couples WS5's Retry, not reactions). **Room first-paint:** messages render **inline server-side** (no lazy fetch), so a "before the page arrives" skeleton has no slot — implement as a Turbo-navigation skeleton (Stimulus on `turbo:before-visit`→`turbo:load`) or scope to the sidebar frame; do **not** move messages to client-render (designer boundary).
- **Live connection-lost banner (④):** detect disconnect via AnyCable/`HeartbeatChannel` and show the in-surface banner (copy already reskinned via the flash tokens; this adds the live trigger).
- **Message Retry (④):** failed-send shows the `.message--failed` treatment; add the Retry action + resend/reconcile (couples the composer).
- **Tests-first:** disconnect→banner; retry→resend.

## WS6 — Auth completion

> **✅ Built.** Six-box OTP, in-card alerts, "Send another" resend. The expired-link view was handled via the recovery loop instead of a dedicated view — see Build status.

- **Six-box OTP input (REBUILD, headline):** replace the single `.input--otp` (`auth.css:274-281`, `app/views/sessions/_code_field.html.erb`) with six discrete cells + a Stimulus controller: per-cell focus-advance/backspace, **paste-split across all six**, display normalization (upper-case, O→0, I/L→1, strip spaces/dashes) writing into a hidden concatenated `code` field; active cell gets the accent highlight. Server still receives one `code` param — no controller change.
- **In-card alerts (RESKIN):** move the flash render **into** the card on the session-layout pages (from the floating pill, `app/views/layouts/session.html.erb:35-47`); add the amber `alert` tone to `.auth-card__alert` (today neg + positive only).
- **Code screen (RESKIN):** "Didn't get it? **Send another**" resend + the mode-unavailable copy when `AUTH_METHOD≠otp` (`app/views/auth_tokens/validations/new.html.erb:23-25`).
- **Expired-link view (verify/small):** confirm a dedicated view exists; if not, a small card view with the quiet CTA (reuse `.auth-card__action--quiet`).
- **Tests-first:** OTP paste-split + normalization.

---

## Sequencing & commit boundaries

Mirror the designer's build order (as Phase 1 did), each workstream shippable on its own:

1. **WS0 Type** — foundation, first (ripples everywhere).
2. **WS6 Auth** — low-risk, high-volume; good early momentum (like Phase 1 Step 5).
3. **WS1 Responsive** — broad CSS + two Stimulus.
4. **WS3 Reactions reskin/dialogs/composer** + **WS5 States** — do adjacent.
5. **WS4 Inbox data** — isolated query work.
6. **WS2 Contextual panel** — highest structural risk; its own careful series, once the rest is stable.

Each workstream = one commit or a small bisectable series. **Resolved:** Phase 2 is continuing on `redesign-v2` (still unpushed, no PR). Actual order so far: WS0 → WS1 → WS6 → WS4. (WS1 pulled ahead of WS6 to close the WS0 `ch`-coupling promptly; WS4 pulled ahead of WS3/WS5 as the self-contained, decision-free block — its verb-row/card/query work has no coupling to the reactions or states rebuilds.)

## Verification

- **Per workstream:** targeted system tests matched to the change; tests-first for every behavior rebuild (OTP, connection banner, skeletons, mini-composer, panel swap).
- **Per boundary:** full unit (`bin/rails test`), the tight system wall, SaaS (`SAAS=true bin/rails test saas/test/`), light+dark screenshots of touched surfaces.
- **Parity:** verify each step under `native.css` (Hotwire Native) and SaaS views.
- **Designer boundary check:** no routes/models/controllers/Turbo-target/partial-structure change **except** the sanctioned ④ data item — the activity/thread queries (WS4). WS3 no longer changes the boost model — reactions are reskin-only.

## Out of scope (record, don't silently drop)

- **Aggregated + optimistic reactions rebuild** — reactions work today (per-user chips), so Phase 2 reskins the chips only. Recorded for a future functional pass: the aggregation query already exists (`Message#boost_summary` → `Boost::Group`, tested, used by the bot API), so the real work is reshaping the boost broadcast/stream pipeline (`broadcast_create`/`broadcast_removal`/`create.turbo_stream.erb`) from per-chip append/remove to a per-emoji-group replace (a Turbo-target change) — with the three shadow paths (2nd reactor → update, non-last removal → decrement, last removal → delete) and the per-chip delete/repeat affordance moving into the group chip — plus optimistic insert reconciled on `(booster_id, content)` since boosts carry no `client_message_id`.
- **Pinned-messages bar** — net-new Pin model/endpoints; product sign-off like Huddle. Leave the header slot free.
- **Huddle** button/panel — net-new feature.
- **Composer persistent format bar** — until the Trix→Lexxy migration lands (P2-2).
- **Compact density toggle** (C5).
- **Server-side message grouping** — stays client-side (C3).
