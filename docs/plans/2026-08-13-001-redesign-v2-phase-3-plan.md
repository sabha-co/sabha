# Plan: Sabha v2 redesign — Phase 3 (audit gap closure)

**Status:** draft (review) · **Date:** 2026-08-13 · **Builds on:** Phase 2 (`redesign-v2`, complete except the composer emoji button, unpushed) · **Source of truth:** `~/dev/design_handoff_sabha_v2` (design references, not code)

> **What this is.** After Phase 2 closed out, a full screen-by-screen audit compared the running app against every surface the handoff draws (all twelve Desktop screens, the States and Auth prototypes, and the redline markup — including states the rendered comps hide, which is how the header member pill was missed the first time). The core surfaces match. What remains is a concrete list: two shape-level divergences (search, DMs), one IA divergence (settings), one header element, an inbox polish cluster, and a handful of details. Phase 3 closes that list.

> **Scope stance.** Same discipline as Phase 2: routes, models, controllers and Turbo targets don't change unless a workstream explicitly flags otherwise. Behavior rebuilds get tests first. Nothing here is a net-new feature — every item recreates something the handoff draws for a surface that already exists.

## Owner decisions to confirm before the flagged workstreams

1. **Member-pill target (WS2).** The comp's header pill (`👤 124`) opens the community-wide **members directory**, not the room roster — even though the count shown is the room's. Proposed: follow the comp. Alternative: open the roster panel (arguably more natural; the ⓘ next to it already opens the roster, which argues for the comp's split).
2. **DM split view (WS5) — build or defer.** The largest layout change left. The comp draws a persistent conversation-list column beside the open DM. Everything else in this plan works without it.
3. **Settings consolidation (WS6) — build or defer.** Second large item: one two-pane settings surface with a section nav replacing today's separate card pages. Content parity already exists; this is shell + navigation work.
4. **Profile "status" field (WS4, one item).** The comp has "What are you up to?" (shown in the footer chip) *distinct from* Bio. Today the chip shows `bio || "Here now"`. Matching the comp needs a new `users.status_message` column — the one schema change in this plan. (`users.status` is taken: it is the existing active/deactivated/banned account-state enum gating login and moderation, and is untouchable.) Skippable independently.

---

## WS1 — Search as a ⌘K palette (structural, highest value-to-effort)

The comp's Search is a command-palette overlay, not a page: floating card near the top of the viewport, "Search messages across every room you can see" input, RECENT SEARCHES chips, ESC hint. The app has a dedicated page with a composer-style input at the *bottom*.

- Rebuild on the existing **scrim-dialog primitive** (`dialog_controller` + `.scrim-dialog`), mounted in the layout like the reaction picker; a variant class tops-aligns the card (the primitive centers by default).
- The palette is the *entry point*; submitting still navigates to `searches_path` with results rendering on the existing results page (routes and `SearchesController` unchanged). The sidebar Search row and the composer search button open the palette instead of navigating.
- Recent searches render as chips in the palette. The layout-mounted partial queries `Current.user.searches.global.ordered` directly (with a limit) — `@recent_searches` is assigned only by `SearchesController#index`, so a layout mount can't rely on the ivar. Clearing stays (`clear_searches_url`).
- **⌘K / Ctrl-K** global shortcut opens it; the sidebar row gets the `⌘K` hint (shown only on fine-pointer devices).
- The results page keeps its nav treatment but its input moves to the top of the results column (comp's reading order), dropping the bottom composer-style bar.
- **Tests first:** palette opens via shortcut and sidebar row, ESC closes, submit navigates to results, recent-search chip navigates.

## WS2 — Header member pill (small; my Phase-2 miss)

- Restore the member count to the room header as the comp's pill: `👤 {count}` — bordered, radius-full, 12px/600, `fg2` — sitting **between the room name and the topic**, alongside (not replacing) the ⓘ roster button.
- Target per owner decision #1 (default: members directory).
- Hide on thread headers and DMs (comp shows it on rooms; a DM's "2 members" pill is noise — the DM header work is WS5).
- Drop at <834 per the original WS1 header-drops intent (the element finally exists to drop).

## WS3 — Inbox polish cluster (view/CSS work, no new queries except two counts)

**Activity** (`inboxes/_nav` yield + `notifications/_activity`):
- Header annotation "N unread" beside the title. **Unread semantics (owner-decided): since-last-visit.** Notifications carry no per-row read state — the signal is the `activity_seen_at` watermark, and `#index` advances it as it renders. The controller passes the pre-touch watermark to the view; the count and the per-row dots derive from `created_at > watermark`, so markers show what arrived since the previous visit and clear on the next load. No controller behavior change, and the sidebar dot's `unseen_activity?` semantics stay untouched.
- **Mark all read** action right-aligned in the bar — the endpoint already exists: `Inboxes::ClearancesController#create` (`inbox_clearance_path`) calls `Current.user.mark_inbox_as_read`, including the activity watermark and membership counter resets. Wire the button to it; no new controller action.
- **Today / Earlier** group labels (render-time grouping, no query change). The list appends paginated `_items` pages, so labels must dedupe across page boundaries — mirror the message day-separator approach rather than emitting labels only at first render.
- Per-row unread dot, right-aligned, accent (same since-last-visit signal as the header count).
- Timestamps go compact-relative ("10:02 AM", "Yesterday") via the existing `local_time` machinery, replacing "9 July 2026 at 16:33".

**Threads** (`inboxes/threads/_thread_card`):
- Header subtitle "N threads you follow".
- Card chrome: bordered, radius-12 cards with padding (currently a flat hairline list); unread cards get the accent tint the comp draws.
- Footer reply-row facepile: small overlapping avatars (comp ~18px, −5 overlap) instead of full-size; reuse the forum-card stack pattern.

**Bookmarks** (least converged — full card rebuild):
- Card per bookmark: room link + "saved {relative time}" + inline **Remove** (the Bookmark model has creation time; Remove = existing bookmark destroy endpoint).
- Message body renders inside the card as the comp draws (author, time, text) instead of the raw search-result row.

**Tests:** render tests for grouping/annotations; system test for Mark all read and bookmark Remove.

## WS4 — Detail polish (one commit series, mostly CSS/copy)

- **Jump to newest**: labeled accent pill ("Jump to newest ↓") replacing the round icon button (`button_to_jump_to_newest_message` + messages.css).
- **NEW SINCE LAST VISIT** divider: the comp's red, right-anchored label treatment (today: centered accent-indigo). Red here is the comp's deliberate exception to the accent system — confirm against the token spec's `--negative`/unread token before hardcoding.
- **Sidebar**: section counts ("ROOMS 8", "FORUMS 3", "DIRECT MESSAGES 5", "FAVORITES 2"); a "Browse all rooms →" row at the end of the rooms list (route exists; the ⋯ menu entry can stay); numeric unread badges on DM rows (`membership.unread_notifications_count` — rooms rows already do this); presence dots on DM row avatars (connected-scope, same signal as the roster); `⌘K` hint on the Search row (couples WS1).
- **Composer placeholder**: "Message #general" / "Message {first name}" via a `placeholder` on the rich-text field (verify Trix respects it; if not, CSS `:empty::before` on the editor — solved, not skipped).
- **Profile status field** per owner decision #4: `users.status_message` column, "What are you up to?" input on the profile page, footer chip shows `status_message || "Here now"`, Bio stays Bio. (Skippable independently.)
- **Error pages**: leave the system font stack (they load without the asset pipeline) — recorded as accepted, not a gap.

## WS5 — DM split view (large; owner gate #2)

- The comp: DM tool opens a two-pane surface — conversation-list column (~280px; rows: avatar + presence dot, name, time, last-message snippet, unread badge) with the open conversation beside it. Conversation header: name + **"Here now" presence subtitle** + **View profile** button; DM headers drop the ⓘ roster button.
- Header fallbacks (the codebase supports both): presence subtitle and View profile render only for 1:1 DMs (exactly one other member); group DMs show an "N members" subtitle with no View profile; Note-to-self shows the name only.
- Proposed shape: the DM inbox page becomes the split surface; opening a DM at a `/rooms/:id` URL with `Rooms::Direct` renders the same two-pane layout (list + conversation), so both entries converge. Below 1024 the list is its own screen and the conversation is full-width with a back link — the app's current behavior, kept.
- Routes unchanged. Flagged per the scope stance: the conversation pane gets a **new Turbo frame**, and direct-room rendering extends to load the conversation-list data currently assembled by `Inboxes::DirectMessagesController` (with the same preload care the inbox list already takes). Otherwise layout + a shared list partial — the DM-inbox list already renders conversation rows with snippets and becomes the column.
- Presence subtitle reuses the roster's connected/last-seen buckets for the other member.
- **Tests first:** split renders at desktop, list row opens conversation in place, mobile keeps full-width + back.

## WS6 — Settings consolidation (large; owner gate #3)

- One settings surface, two-pane: left section nav, right content. **Community** (admin): Identity / Invitations / Badges / Permissions / Bots & webhooks. **Your settings**: Profile / Appearance / Notifications / Account & data. Cross-links between the two ("Your settings ›" / "Community settings ›").
- The existing pages keep their routes and controllers — each mounts inside the shared settings shell (a layout partial with the section nav, current section highlighted), so this is IA/shell work, not a rewrite. Content is already v2-skinned.
- Map: Identity = account/edit identity card · Invitations = join-code/invite surface · Badges = accounts/badges · Permissions = the restriction toggles (today on account/edit) · Bots & webhooks = accounts/bots · Profile = users/me/profile · Appearance = theme + accent (accent is admin — lives Community-side per comp's Permissions/Identity split; verify against comp) · Notifications = notification settings page · Account & data = email change / sessions / export-ish (map what exists; invent nothing).
- Below 834 the section nav collapses to a screen of links (standard pattern).
- **Tests:** navigation renders each section inside the shell; no controller behavior changes.

---

## Round 2 — full-page screens the phase plans missed (owner-approved 2026-08-13)

A second audit after WS1–WS6 shipped found four screens the Desktop comp draws that never got the v2 shell: they still render as v1 floating `.panel` cards under the transparent fixed nav, with no sidebar. All four are comped; none were itemized in any phase. The owner approved closing all four. The shared move is the one the settings shell proved: give each screen `@body_class = "sidebar …"`, the sidebar frame, an in-flow navbar (title + subtitle + trailing action — the comp's 54px header bar *is* our navbar), and a max-width content column. Content largely exists; this is shell + layout work with a few flagged data touches.

### WS7 — Profile page (`users#show`)

The comp: an in-shell 720px reading column. Identity header — 88px radius-22 avatar with an 18px presence dot, name 24/700 with role glyph and uppercase badge chip, "‹ Back" quiet accent link above, presence line "Here now · joined {Mon YYYY}", bio at 14.5/1.6. Action row: **Message** (accent primary), **All messages** (outlined), **Block/Unblock** (outlined; negative fg when it reads Unblock). Stats: three bordered radius-12 cards. RECENT MESSAGES section label + a bordered card list (accent room link + compact time, message text; row links to the message). Staff-only **Moderation** card (Deactivate quiet / Ban negative) with the existing explainer copy.

- Rebuild `users/show` inside the shell; bot / banned / deactivated variants keep their reduced content in the same column.
- Stats mapping: MESSAGES = `total_message_count`; **DAY STREAK** stays day (comp says WEEK STREAK — we track day streaks; recorded deviation, not a new computation); third card = **SHARED ROOMS** (flagged: one new count query — rooms where both users hold active memberships) since "joined" moves into the presence line per comp.
- Kept beyond the comp: social links, admin-only email link, the pencil→settings link on your own profile.
- The buried "All messages from X" footer link becomes the action-row button.

### WS8 — Members directory (`accounts/users#index`)

- Shell + navbar: back, "Members" title, count-line subtitle, trailing **Manage badges** accent text link (admins). The v1 icon buttons (badges/bots/home) drop — bots live in the settings shell now.
- Toolbar row under the navbar: the existing debounced search field + the existing status segmented control (staff).
- Content: 820px column; role sections become bordered radius-12 cards with hairline-divided rows (the row innards are already v2 from the role-menu work — untouched, as is the `account_users` turbo-frame + manage dialog).

### WS9 — Browse rooms (`rooms/browse#index`)

- Shell + navbar: "Browse rooms" title, subtitle, trailing **New room** accent button (replaces the off-token green).
- Content: 760px column; the card list and "Show 20 more" pagination already ride `.browse-card`/`.list-row`.
- **Flagged query change (follow the comp):** the comp lists *every* visible room — "Every room you can see, joined or not" — with joined rooms showing a quiet **Joined** state instead of the accent **Join** button. Extend the browse scope to include joined rooms; row title links into the room; Joined renders as a non-destructive quiet chip (leaving stays in room settings — the comp's toggle-to-leave is not worth the accident risk).

### WS10 — Room settings (`rooms/{opens,closeds,forums}#edit` via `layouts/_tabbed_edit`; directs/threads via `layouts/_edit`)

- Shell for both layout partials + navbar: "‹ {room name}" back + "Room settings" title. Content column 640px.
- **Tab consolidation per comp: two tabs, not three.** The comp's Settings tab holds the name/description card ("Renaming posts a line in the room so nobody wonders what happened." helper), the access card (Open-to-everyone + Add-new-members-automatically toggles, auto-join disabled-looking when closed), and one Leave/Delete card (Leave quiet row, Delete negative row, delete disabled on the original room). Today About (form) / Members / Settings are three tabs with the access toggle living at the top of the *Members* panel — merge About into Settings and move the access toggles there. Notifications (involvement select + hide toggle) stays in the Settings tab — app content the comp doesn't draw, kept.
- Members tab: "Add someone by name" input + "In this room" bordered card (count header, member rows with Remove) — restyle the existing `member-toggle` machinery, don't rewrite it.
- Non-admins: name/description read-only, Members + Settings tabs as today, inside the shell.
- Directs/threads keep the untabbed `_edit` — same shell and column, existing content (notifications, block toggle, delete conversation).

### Round 2 sequencing

7. **WS7 Profile** — biggest visible gap, self-contained.
8. **WS8 Members** — quick re-shell.
9. **WS9 Browse** — quick re-shell + the flagged scope change.
10. **WS10 Room settings** — last; the tab consolidation is the largest interior change.

Not gaps (recorded as intentional): email unsubscribe pages, incompatible-browser, join/first-run, push-subscriptions dev page, and the About page — none are drawn in the comps; they stay token-inheriting cards.

---

## Sequencing & commit boundaries

1. **WS2 member pill** (small, immediate — restores a comp element the header rebuild dropped).
2. **WS1 search palette** (structural, highest value; unlocks the WS4 ⌘K hint).
3. **WS3 inbox cluster** (three bisectable commits: Activity, Threads, Bookmarks).
4. **WS4 detail polish** (small series; status-field item gated on decision #4).
5. **WS5 DM split view** — after owner confirms (#2).
6. **WS6 settings consolidation** — after owner confirms (#3); last, biggest shell change.
7. **WS7–WS10** — Round 2 per its own sequencing above.

Each workstream = one commit or a small bisectable series on `redesign-v2` (still unpushed; push/PR only on explicit approval).

## Verification

- Tests-first for every behavior rebuild (palette, mark-all-read, DM split, bookmark remove); targeted system walls matched to each change; full unit + SaaS (`unset UNTENANTED_DATABASE_URL; SAAS=true bin/rails test saas/test/`) at every boundary.
- Light + dark live screenshots of touched surfaces; drawer/rail/desktop widths for WS1, WS5, WS6.
- Designer-boundary check per workstream: the only schema change is the optional status column (WS4); the plan adds zero new endpoints (mark-all-read reuses `inbox_clearance_path`).

## Out of scope (record, don't silently drop)

- **Huddles** (header chip, banner, panel) and the **pinned-messages bar** — deferred features; header slots stay free.
- **Composer format bar, @/# inserts, emoji button** — await the Trix→Lexxy migration.
- **Forum post as a full page** with header Copy link/Follow/Reopen — the post stays in the wide contextual panel (owner call recorded in Phase 2 / WS2).
- **Server-side message grouping** — stays client-side.
- **Error-page typeface** — system stack accepted for static pages.
