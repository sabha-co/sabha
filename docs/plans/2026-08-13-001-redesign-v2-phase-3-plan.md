# Plan: Sabha v2 redesign — Phase 3 (audit gap closure)

**Status:** draft (review) · **Date:** 2026-08-13 · **Builds on:** Phase 2 (`redesign-v2`, complete except the composer emoji button, unpushed) · **Source of truth:** `~/dev/design_handoff_sabha_v2` (design references, not code)

> **What this is.** After Phase 2 closed out, a full screen-by-screen audit compared the running app against every surface the handoff draws (all twelve Desktop screens, the States and Auth prototypes, and the redline markup — including states the rendered comps hide, which is how the header member pill was missed the first time). The core surfaces match. What remains is a concrete list: two shape-level divergences (search, DMs), one IA divergence (settings), one header element, an inbox polish cluster, and a handful of details. Phase 3 closes that list.

> **Scope stance.** Same discipline as Phase 2: routes, models, controllers and Turbo targets don't change unless a workstream explicitly flags otherwise. Behavior rebuilds get tests first. Nothing here is a net-new feature — every item recreates something the handoff draws for a surface that already exists.

## Owner decisions to confirm before the flagged workstreams

1. **Member-pill target (WS2).** The comp's header pill (`👤 124`) opens the community-wide **members directory**, not the room roster — even though the count shown is the room's. Proposed: follow the comp. Alternative: open the roster panel (arguably more natural; the ⓘ next to it already opens the roster, which argues for the comp's split).
2. **DM split view (WS5) — build or defer.** The largest layout change left. The comp draws a persistent conversation-list column beside the open DM. Everything else in this plan works without it.
3. **Settings consolidation (WS6) — build or defer.** Second large item: one two-pane settings surface with a section nav replacing today's separate card pages. Content parity already exists; this is shell + navigation work.
4. **Profile "status" field (WS4, one item).** The comp has "What are you up to?" (shown in the footer chip) *distinct from* Bio. Today the chip shows `bio || "Here now"`. Matching the comp needs a new `users.status` column — the one schema change in this plan. Skippable independently.

---

## WS1 — Search as a ⌘K palette (structural, highest value-to-effort)

The comp's Search is a command-palette overlay, not a page: floating card near the top of the viewport, "Search messages across every room you can see" input, RECENT SEARCHES chips, ESC hint. The app has a dedicated page with a composer-style input at the *bottom*.

- Rebuild on the existing **scrim-dialog primitive** (`dialog_controller` + `.scrim-dialog`), mounted in the layout like the reaction picker; a variant class tops-aligns the card (the primitive centers by default).
- The palette is the *entry point*; submitting still navigates to `searches_path` with results rendering on the existing results page (routes and `SearchesController` unchanged). The sidebar Search row and the composer search button open the palette instead of navigating.
- Recent searches render as chips in the palette (data already exists — `@recent_searches`); clearing stays (`clear_searches_url`).
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
- Header annotation "N unread" beside the title (count of unread notifications — scope exists for the badge already).
- **Mark all read** action right-aligned in the bar (`Notification` bulk-read — check for an existing endpoint; if absent this is the one new controller action in the plan, RESTful as `inbox/notification_reads#create`… verify against existing read-tracking first, the unread badge implies most plumbing exists).
- **Today / Earlier** group labels (render-time grouping, no query change).
- Per-row unread dot, right-aligned, accent.
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
- **Profile status field** per owner decision #4: `users.status` column, "What are you up to?" input on the profile page, footer chip shows `status || "Here now"`, Bio stays Bio. (Skippable independently.)
- **Error pages**: leave the system font stack (they load without the asset pipeline) — recorded as accepted, not a gap.

## WS5 — DM split view (large; owner gate #2)

- The comp: DM tool opens a two-pane surface — conversation-list column (~280px; rows: avatar + presence dot, name, time, last-message snippet, unread badge) with the open conversation beside it. Conversation header: name + **"Here now" presence subtitle** + **View profile** button; DM headers drop the ⓘ roster button.
- Proposed shape: the DM inbox page becomes the split surface; opening a DM at a `/rooms/:id` URL with `Rooms::Direct` renders the same two-pane layout (list + conversation), so both entries converge. Below 1024 the list is its own screen and the conversation is full-width with a back link — the app's current behavior, kept.
- Routes unchanged; this is layout + a shared list partial (the DM-inbox list already renders conversation rows with snippets — it becomes the column).
- Presence subtitle reuses the roster's connected/last-seen buckets for the other member.
- **Tests first:** split renders at desktop, list row opens conversation in place, mobile keeps full-width + back.

## WS6 — Settings consolidation (large; owner gate #3)

- One settings surface, two-pane: left section nav, right content. **Community** (admin): Identity / Invitations / Badges / Permissions / Bots & webhooks. **Your settings**: Profile / Appearance / Notifications / Account & data. Cross-links between the two ("Your settings ›" / "Community settings ›").
- The existing pages keep their routes and controllers — each mounts inside the shared settings shell (a layout partial with the section nav, current section highlighted), so this is IA/shell work, not a rewrite. Content is already v2-skinned.
- Map: Identity = account/edit identity card · Invitations = join-code/invite surface · Badges = accounts/badges · Permissions = the restriction toggles (today on account/edit) · Bots & webhooks = accounts/bots · Profile = users/me/profile · Appearance = theme + accent (accent is admin — lives Community-side per comp's Permissions/Identity split; verify against comp) · Notifications = notification settings page · Account & data = email change / sessions / export-ish (map what exists; invent nothing).
- Below 834 the section nav collapses to a screen of links (standard pattern).
- **Tests:** navigation renders each section inside the shell; no controller behavior changes.

---

## Sequencing & commit boundaries

1. **WS2 member pill** (small, immediate — restores a comp element the header rebuild dropped).
2. **WS1 search palette** (structural, highest value; unlocks the WS4 ⌘K hint).
3. **WS3 inbox cluster** (three bisectable commits: Activity, Threads, Bookmarks).
4. **WS4 detail polish** (small series; status-field item gated on decision #4).
5. **WS5 DM split view** — after owner confirms (#2).
6. **WS6 settings consolidation** — after owner confirms (#3); last, biggest shell change.

Each workstream = one commit or a small bisectable series on `redesign-v2` (still unpushed; push/PR only on explicit approval).

## Verification

- Tests-first for every behavior rebuild (palette, mark-all-read, DM split, bookmark remove); targeted system walls matched to each change; full unit + SaaS (`unset UNTENANTED_DATABASE_URL; SAAS=true bin/rails test saas/test/`) at every boundary.
- Light + dark live screenshots of touched surfaces; drawer/rail/desktop widths for WS1, WS5, WS6.
- Designer-boundary check per workstream: the only schema change is the optional `users.status`; the only new endpoint candidate is mark-all-read (verify existing plumbing first).

## Out of scope (record, don't silently drop)

- **Huddles** (header chip, banner, panel) and the **pinned-messages bar** — deferred features; header slots stay free.
- **Composer format bar, @/# inserts, emoji button** — await the Trix→Lexxy migration.
- **Forum post as a full page** with header Copy link/Follow/Reopen — the post stays in the wide contextual panel (owner call recorded in Phase 2 / WS2).
- **Server-side message grouping** — stays client-side.
- **Error-page typeface** — system stack accepted for static pages.
