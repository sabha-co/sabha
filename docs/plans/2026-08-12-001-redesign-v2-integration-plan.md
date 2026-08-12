# Plan: Sabha v2 redesign — integration against the current repo

**Status:** draft (review) · **Date:** 2026-08-12 · **Ships as:** **2 PRs** — PR 1 the token foundation (Step 1), PR 2 the redesign (Steps 2–6, one bisectable commit series) · **Source:** `~/dev/design_handoff_sabha_v2` (design references, not code)

> **What this is.** A deep-review of the v2 design handoff against the code as it stands today, plus a build-order integration plan. The handoff bundle is the visual/interaction source of truth; this doc reconciles it with what the repo actually contains and calls out where the two disagree. Nothing here is a visual-design decision — that stays designer-led. This is prep + integration scoping.

> **Scope: reskin/redesign, with one sanctioned feature exception.** This pass restyles existing surfaces; routes, models, controllers, and broadcasts don't change — **except** the workspace **accent system** (see C1), which the owner has explicitly chosen to build now even though it's net-new. **Huddles (live audio) is explicitly NOT in this plan** — it is a net-new feature that ships *after* the redesign, in a later pass. Build the redesign without it: leave the room-header slot free so it can be added later without reflowing (Step 2), but do not scope, design, or implement any Huddles model/channel/route/UI here.

## Confirmed directions (owner call, 2026-08-12)

The handoff (`README.md`, `github.md`) is a proposed direction, not settled instruction. These four forks are now decided:

| # | Fork | Decision | Effect on plan |
|---|---|---|---|
| **C1** | **Accent system** — five selectable workspace accents; none exists in code today | **Build all five now** (Indigo/Ink/Forest/Rust/Plum + `[data-accent]`) | The one net-new feature. **Split:** the token *scaffold* (indigo default, invisible) lands in **Step 1**, colour-only; the *picker + `account.settings.accent` persistence* lands with **Step 5** (`/account`, already being re-skinned). See **D6**. |
| **C2** | **Sidebar** — right → left, dark contrast by default | **Left + dark contrast** (full v2 move) | Step 2 proceeds as the handoff specs it. Largest structural change; ship it alone. |
| **C3** | **Message grouping** — client-side today vs handoff's server-side rebuild | **Keep client-side**; optional server first-paint hint only | No grouping rewrite. `message_formatter.js` stays the runtime truth. Resolves D-Group. |
| **C4** | **Typography** — system stack today vs handoff's Instrument Sans | **Adopt Instrument Sans** (UI face) | New web font. **Self-host** the woff2 (don't hotlink Google Fonts — this is a self-hostable, privacy-minded app). `CLAUDE.md`'s "system font stack" line goes stale and must be updated when this lands. |
| **C5** | **Density** — handoff defines comfortable + compact modes | **Ship comfortable as fixed values; defer the compact toggle** | No density setting/feature this pass (unlike accents). `--space-row`/`--space-msg` land as fixed comfortable values in Step 1; the compact variant + user toggle is deferred and can be added later without rework. |

> **Path note.** Bare filenames are shorthand: `colors.css`, `messages.css`, `sidebar.css`, `layout.css`, `nav.css`, `composer.css` → `app/assets/stylesheets/application/*.css`; `application.css` (the Tailwind entry) → `app/javascript/entrypoints/application.css`; `overrides.css` → `app/assets/stylesheets/application/overrides.css` (loaded **last**, wins the cascade); `message_formatter.js`, `messages_controller.js`, `composer_controller.js` → `app/javascript/{models,controllers}/*.js`. View paths given in full.

---

## Part A — Where the handoff and the repo disagree

The handoff is careful and mostly accurate, but four assumptions in it don't match the code. These change scope, so settle them before building.

| # | Handoff says | Repo actually | Impact |
|---|---|---|---|
| **A1** | "the four `resource :inbox` surfaces… that were stubs" (README build order §4; github.md "Built the four inbox surfaces that were stubs") | **Fully built, and there are six**: `activity`, `direct_messages`, `threads`, `bookmarks`, **plus `notifications` and `messages`**. Real query objects (`app/models/inbox/*_query.rb` — five; `notifications` reuses `MessagesQuery` with an involvement filter, so it has no query file of its own — see D#3); complete controllers + `app/views/inboxes/` partials. | Step 4 inbox work is **re-skin, not build**. Lower risk, but the redesign must account for `notifications` + `messages` surfaces the handoff never drew. |
| **A2** | States doc: "`public/502.html` (26 KB) and `public/400.html` / `public/422.html` — not read yet"; implies error-page coverage is thin | **All six already exist**: `public/{400,404,406-unsupported-browser,422,500,502}.html`. | Step 6 is smaller than billed. Only genuinely new pages: **403** and **offline**. 404/500 are copy-replacements; 406 is a copy tweak. |
| **A3** | Redlines: "the action bar is hover-only today **in `messages.css`**" | The authoritative reveal rule is in **`overrides.css:129-137`** (`.message__options-btn{opacity:0}` → `.message:hover …{opacity:1}`), and `overrides.css` loads last. `messages.css` only has per-button `:focus-visible`. | The `:focus-within` fix must land in **overrides.css** (or respect its precedence), or it's silently overridden. |
| **A4** | Redlines/README: "grouped follow-on messages **need a server-side decision in the partial** (same author, under 5 min); CSS only removes the avatar and meta" — stated as if it's not yet done | Grouping **already exists and is entirely client-side**: `message_formatter.js` (`THREADING_TIME_WINDOW_MILLISECONDS`, same `data-user-id`, non-event previous sibling) toggles `message--threaded`; `messages_controller.js` re-threads siblings on live insert/delete. The server partial has **no** grouping logic. | This is the one **architectural** ask in the handoff, and it's the riskiest. See **D-Group** below — moving it server-side as written will break live-inserted messages. Recommend a hybrid, not a rewrite. |

### D-Group — the grouping decision (Resolved — see C3)

The handoff wants grouping decided server-side "in the partial." That's clean for **first paint**, where all messages render together. It breaks for the **real-time path**: a broadcast renders one message's partial in isolation, with no knowledge of the previous DOM sibling's author or timestamp — which is exactly why the current code does it in JS, and re-threads neighbours after inserts and deletes.

**Decision (C3):** keep `message_formatter.js` as the runtime source of truth. Optionally add a server-rendered *first-paint hint* (partial sets `message--threaded` when it can see the prior message in the same render pass) to kill the group-in/regroup flash on load, but do **not** remove the JS. Framing "the partial decides" as the whole mechanism is a feasibility miss for a live chat stream. The designer only needs to confirm the *visual* result (avatar/meta suppressed, padding 9) — not where the boolean is computed.

---

## Part B — Build-order integration plan

Order follows the README (tokens first, or every component is built twice). **PR packaging (2 PRs — owner call): PR 1 = Step 1** (the token foundation, colour-only, lands alone so a palette regression stays isolatable from layout changes); **PR 2 = Steps 2–6** (the redesign), developed in that order as separate, bisectable commits on one branch and merged together. The six steps below are PR 2's internal build/commit sequence — *not* six PRs; each step's **commit boundary** note says how to keep that history reviewable. (A long-lived PR 2 will need periodic rebases on `main`.)

### Step 1 — Token layer (do first; no visual change beyond colour)

**v2 intent:** three layers — primitives (`--lch-*`), semantic (`--color-*`), scopes (dark / `[data-accent]` / contrast sidebar). `colors.css` becomes the *single* value declaration; `@theme inline` only re-exposes names to Tailwind. Add surfaces (bg / raised / sunk / hover), a 4-tier text ramp, retune status hues down, add the 5-accent set, add radius + density + elevation scales.

**Current state (verified):**
- LCH primitives are declared **three times**: `colors.css:3-18`, `application.css:114-129` (`:root`), and `application.css:12-27` (`@theme` as `--color-lch-*`). Because `colors.css` loads *after* the compiled `tailwind.css`, **its values already win at runtime** — so the handoff's "colors.css is the single declaration" aligns with today's effective behaviour.
- The 17 semantic `--color-*` names are declared twice (`colors.css:21-37` vs `application.css:30-46`).
- shadcn alias value blocks (`--background/--foreground/--primary/…/--ring`) are written out **four times** in `application.css` (light `:root` 133-145, `@media dark` 177-190, `[data-theme=light]` 239-252, `[data-theme=dark]` 298-311). Code-syntax colours and `--shadow-base` repeat across the same four blocks.
- Dark mode is handled **three ways** (bare `@media prefers-color-scheme:dark`, `[data-theme=light]`, `[data-theme=dark]`) in `application.css`, plus `colors.css:42-59` handles the auto case only. Matches the handoff's "dark declared three times — collapse first" check.
- **No radius token exists anywhere** — every v2 radius (`--radius-sm/md/lg/pill`) is net-new.
- **Two parallel spacing systems**: `@theme` `--spacing-*` (largely unused) vs `utilities.css:2-8` `--inline-space*`/`--block-space*` (what components actually consume; `messages.css:814` re-declares `--block-space` locally). v2 density tokens (`--space-row`, `--space-msg`) are net-new, separate again. Ship the **comfortable** values as fixed (C5); no compact variant or toggle this pass.
- `--hover-color` = `--color-border-darker` (`base.css:4`), the focus/hover **ring** drawn as box-shadow (`--hover-size`). Confirms collision #2 — don't overload it; add `--color-bg-hover` for the fill.
- Live inconsistency: `--lch-purple` value drifts between the two files (`colors.css` 50%/72% vs `application.css` 45% 0.32 / 70% 0.32). It backs `--color-contrast`, slated to retire.

**Retirement scope (verified):** `--color-message-bg` → **6 files / 15 refs**; `--color-contrast` → **1 file / 2 refs** (`messages.css:367,372`); `--shadow-base` → 0 CSS `var()` callers (but it feeds a Tailwind `shadow-base` utility — grep ERB before deleting). **The shadcn-alias retirement is essentially free:** a class-scoped grep finds **zero** shadcn utility classes consumed anywhere (`app/views` and `saas/app/views` both 0 — nothing uses `bg-primary`/`text-primary`/`bg-muted`/etc.), so the aliases can be deleted without migrating a caller. *(Correction: an earlier draft claimed "36× `text-primary` in app views"; that was a substring false-positive — the 36 hits are `var(--color-text-primary, #111)` inside the 5 `saas/app/views/saas/static/*` pages.)* **Separate SaaS-static cleanup (not a shadcn concern):** those 5 pages reference `--color-text-primary`, which is **undefined repo-wide** and renders at its `#111` fallback — already a silent dark-mode contrast fail, and it would rebind if the v2 4-tier ramp ever defines that name. Point them at a real semantic token or keep them literal, independent of the alias retirement.

**Files:** `colors.css`, `application.css` (delete the duplicated `--lch-*` literals + shadcn blocks from `@theme` and thin the four dark blocks to one referenced source), `base.css` (keep `--hover-color`; add nothing that overloads it), `sidebar.css` (contrast-scope block), plus the 6+ retirement callers and the 5 SaaS static pages.

**Risks / decisions:**
- Ship colour-only: no layout/markup/spacing edits in the same commit, so any regression is unambiguous (handoff check).
- Keep logical properties (`inset-inline`, `padding-block`) — the app uses them throughout; the LTR mockups don't threaten that.
- `--color-text-subtle` at oklch 70.3% clears 3:1 but not 4.5:1 — restrict to decorative meta (times, counts, section labels); load-bearing text steps up to `--color-text-muted`.
- **Run both suites** and eyeball light + dark + each accent. The only change is colour — no layout shift, so any reflow is a regression.
- **Accent scaffold here (C1), picker in Step 5 — but this step commits the hue.** The base `:root` interactive tokens (`--color-link`, `--color-selected`/`-dark`, new `--color-accent-brand`) move **blue → indigo** now, so every link, selected row, reaction chip and Send button changes hue app-wide. That *is* the visible change — "colour-only" means no layout/markup shift, not "no change." **Exercise all five accents in this step**, not just indigo: wire a throwaway way to set `data-accent` (a `?accent=` param or a hardcoded dev view) so Ink/Forest/Rust/Plum get a real code path when the tokens land. Eyeball the accent *tints* (selected/reaction-chip fills) across all five in **dark**, where they're accent-at-15%-alpha — forest/rust may not lift on the dark ground. Without this, the one net-new feature's integration risk is deferred whole to Step 5.

**PR 1 (foundation):** the token consolidation + accent scaffold — colour-only, lands first and alone.

**As built (2026-08-12, on `redesign-v2`):** four deviations discovered during implementation, all verified against the code:
- **Radius tokens landed as `--border-radius-sm/md/lg/pill`, not `--radius-*`.** Tailwind's `rounded-lg` utility compiles to `border-radius: var(--radius-lg)` and 12 auth/marketing views use it — declaring the v2 names unlayered in `colors.css` would have silently rebound those cards from 8px to 12px. Steps 2–6 should consume the `--border-radius-*` names. Density (`--space-row`/`--space-msg`) and radius live in `utilities.css` beside the existing spacing tokens; elevation (`--shadow-raise/pop/overlay`) lives in `colors.css`.
- **The code-syntax palette was dead — deleted, not thinned.** `--color-keyword`/`--color-entity`/`--color-markup-*` etc. (4 declaration blocks) have zero consumers anywhere (CSS, ERB, JS); removed outright with the shadcn aliases.
- **One retirement caller the audit missed:** `saas/app/assets/stylesheets/workspace_selector.css` read the Tailwind-emitted `--color-lch-blue/green/white` literals; migrated to `--color-accent-brand`/`--color-positive`/`--color-text-reversed`.
- **SaaS static pages: deferred (owner call, 2026-08-12 — keep the marketing side as is for now).** The 5 static pages render under the `marketing` layout, which loads `marketing/*.css` (its own `--text-primary` world), not `application/colors.css` — so the app-token retirements can't break them, and their undefined `var(--color-text-primary, #111)` keeps rendering at its fallback exactly as before. When marketing is revisited, the fix is marketing's own `var(--text-primary)`, not an app token.
- Dark values are declared once as `--dark-lch-*` primitives in `colors.css`; the media-query and `[data-theme="dark"]` scopes only bind them, and the accent dark story is pure primitive rebinding (`--lch-accent-bg: var(--lch-accent-lift) / 0.15`), so `bg-selected`-style utilities stay dark-correct with no semantic re-derivation. All five accents were exercised in light + dark via a throwaway screenshot harness (JS-set `data-accent`) — no committed toggle was needed; forest/rust lifts read clearly on the dark ground.

---

### Step 2 — Shell & sidebar (the biggest structural move)

**v2 intent:** sidebar moves **right → left**, dark contrast treatment by default (`#17181D`). Three desktop columns ≥1280 (sidebar 272 fixed / main fluid / contextual right panel 360). Responsive: ≥1280 expanded · 1024–1279 a **60px icon rail** that expands on click · 834–1023 rail + thread/DM lists become their own screens · <834 a drawer with ≥44px hit targets. Sidebar order: a **top tool block** (Search / Activity / DMs / Threads / Bookmarks), then **ROOMS**, then **FORUMS**, then **DIRECT MESSAGES**.

**Current state (verified):**
- `body` is a CSS grid, sidebar is the **rightmost** column: `layout.css:5-23` `grid-template-columns: 1fr var(--sidebar-width)`, area on the right, full height. `nav` top-left, `main` bottom-left. Right "panel" today = the **thread panel** as a middle column at the single `120ch` breakpoint (`layout.css:157-178`, max layout `main | thread | sidebar`).
- **Only one shell breakpoint exists: `120ch`.** No `1280/1024/834px`, no drawer state machine. The icon rail is **70px, always-on**, pinned to the sidebar's *right* edge (`sidebar.css:7,17-38`) — not a responsive collapse.
- Sidebar order today: **DMs section first**, then Rooms (Favorites, All Rooms). Tools live in the separate 70px rail: Activity → DMs → Threads → Bookmarks → Account → Bell → Avatar. **There is no Search input in the sidebar** — search is a separate page (`searches/index.html.erb`, `@body_class = "sidebar searches"`). No FORUMS section (forums render inside the rooms list).
- `body.library-collapsed` is **fully styled but never applied** anywhere in Ruby/ERB/JS — dormant machinery (`layout.css:26-62`, read only by `toggle_class_controller.js`).
- `toggle-class` controller (`application.html.erb:104`) drives open/close/focus-trap; its `initial-focus-selector-value="#room-search"` points to an **element that doesn't exist** today.
- CSS load order = alphabetical glob (`lib/stylesheets.rb:16-22`) then `overrides.css` last.

**Gap & files:** `layout.css` (flip grid to sidebar-left; introduce the rail/expanded/drawer states at 1280/1024/834; retire the 120ch overlay), `nav.css`, `sidebar.css` (60px rail, contrast scope `[data-contrast]`), plus the sidebar partial `app/views/users/sidebars/show.html.erb` (reorder into tool-block → ROOMS → FORUMS → DMs; **add the Search entry** — which finally makes `#room-search`/`initial-focus-selector` real), and `toggle_class_controller.js` / a new/renamed collapse controller for the rail-expand-on-**click** behaviour (hover-expand fights drag-reorder — handoff §Interactions).

**Decisions:**
- **`body.library-collapsed`**: delete the dead machinery first (details + rationale in Part D #1), then build the v2 states as fresh explicit classes.
- Forums get their **own** sidebar section (new grouping in the partial), separate from rooms — confirm the data source (STI `Rooms::Forum`) is already available to the sidebar query.
- Contrast sidebar is a **scope, not a theme** (`#sidebar[data-contrast="true"]` rebinds `--color-*`), so it works in both light and dark — from the token spec's paste-ready block.
- Leave the room-header huddle slot free (phase-2), don't reflow for it.
- **Tests first (F3):** no system test covers sidebar open/close/collapse today (5 system tests exist, none touch it). Author them before the shell rewrite, per the tests-before-refactor rule — this is real work inside the step, not a checkbox.

**Commit boundary (PR 2):** the shell move is PR 2's highest-risk part — land it as an early, self-contained commit series (including the `library-collapsed` deletion) so it stays bisectable within the branch.

---

### Step 3 — Message row & composer (two real behaviour changes, not just CSS)

**v2 intent (redlines):** avatar 36 **square** radius 9 (not a circle), 20 from gutter / 12 to text; meta line author 14.5/700 + role glyph + badge chip + time 11.5 + "(edited)" + bookmark; body 15/1.55 one step lighter; reaction chips h23 radius 999 with 17px reactor avatars overlapping −5; **hover action bar floats −12 above the row, flush right, radius 9, pop shadow — 4 quick reactions + picker + Reply + overflow**, appears on hover **and focus-within**. Composer: format bar (B/I/S/`</>` | @ #) h34 above a full-width input, tools (attach/emoji/search) + Send below; **typing indicator pinned above the composer card, outside the scroll container, in a reserved 22px row**; Send goes accent only when the draft is non-empty.

**Current state (verified):**
- Avatar is `--avatar-size: 3.5ch` (`messages.css:380-398`), grid-area `avatar`, with popup `<details>` escaping via `overflow:visible`. v2's 36px-square/radius-9 is a size + shape change; avatars are treated app-wide (`avatars.css`) so this ripples to sidebar DM avatars, list rows, members.
- **Action bar reveal is hover-only in `overrides.css:129-137`** (see A3). Today's bar = inline **Reply** button + an overflow `<details>` menu; **reactions live *inside* the overflow popup** (`_actions.html.erb:30-47`), not as always-visible quick reactions. v2 surfaces 4 quick reactions in a floating bar — a structural change to `_actions.html.erb`, not just CSS.
- Grouping is client-side (A4 / D-Group).
- Composer is **Trix** (`rich_text_area`) — the format bar = the `trix-toolbar`, toggled by `composer_controller.js:83-90`. (Lexxy migration is parked; stay on Trix.)
- Typing indicator today lives **inside the form**, absolutely positioned (`composer.css:130-150`). v2 wants it a **sibling above** `.composer`, outside the scroll container, in a reserved always-present 22px row — a DOM move plus a "never shift the composer" guarantee.

**Gap & files:** `messages.css`, `composer.css`, `overrides.css` (the focus-within reveal must go here — add `.message:focus-within .message__options-btn{opacity:1}` alongside the hover rule, both inside the `@media (hover:hover)` guard so touch keeps its long-press model), `app/views/messages/_actions.html.erb` (surface quick reactions), `app/views/rooms/show/_composer.html.erb` + `app/views/rooms/_composer_fields.html.erb` (move the typing indicator out of the form to a sibling), `avatars.css` (square/radius-9), and `message_formatter.js` (only if we add the first-paint grouping hint per D-Group).

**Behaviour the CSS can't carry (redlines list — carry these into the PR):** focus-within reveal; optimistic reaction chips (appear with your avatar pre-broadcast, revert on disagree); unread separator positioned once on load, cleared on room change not scroll; Send stays enabled while a draft uploads (attachments list above the input); typing pings expire client-side (~4s) on their own timer; your own typing never shows to you; every hover affordance needs a touch long-press equivalent (one menu on phones).

**Tests first (F3):** the action-bar reveal, typing-indicator placement, and client-side grouping have no protective coverage — `message_formatter.js` is untested, and only the typing *broadcast* is tested (`test/channels/typing_notifications_channel_test.rb`), not the DOM move to a reserved sibling row. Write system tests for these before refactoring; treat it as scoped work in this step.

**Commit boundary (PR 2):** keep the row/composer changes as their own commits, separate from the shell commits, so the two regress independently within the branch.

---

### Step 4 — Forum, thread panel, inboxes (re-skin)

**v2 intent:** forum post gallery, forum post surface, thread panel, and the inbox surfaces — all on the shared patterns (segmented control, list row, chips, empty states).

**Current state:** all present and built. Forum: `forum.css` + `app/views/rooms/forums/` (gallery, post cards, filter/solved-toggle). Thread panel: `thread_panel.css` + `panels.css` + `app/views/rooms/threads/`. Inboxes: six surfaces (A1), `app/views/inboxes/` shared `show.html.erb` shell + per-surface `_items` partials; **no `inbox.css`** (leans on `messages.css`/`nav.css`/`layout.css`; DM has `dm_conversations.css`).

**Gap & files:** re-skin against the shared-pattern specs; introduce the **segmented control** and **list row** as reusable partials/CSS (used by activity tabs, forum filters, member status, room-settings tabs, and all five list surfaces — spec once). Consider adding an `inbox.css` rather than overloading `messages.css`. Account for `notifications` + `messages` inbox surfaces the handoff didn't draw (apply the same list-row rhythm).

**Commit boundary (PR 2):** forum + inbox reskin as their own commits (keep forum and inbox separate if the diff is large).

---

### Step 5 — Auth, settings, members, invitations, room CRUD (highest volume, lowest risk)

**v2 intent:** sign-in for all three `AUTH_METHOD` modes + join + first run + expired/signed-out; personal vs admin settings split by permission (staff-only items carry a chip); members directory open to all, grouped by role, with the role menu / badge / deactivate / ban promotion flow; invitations on the real single-join-code model; badges admin; room create/settings/access/leave/delete/browse.

**Current state:** everything maps to existing controllers/views (github.md screen-map is accurate here). `AUTH_METHOD` = `password|otp|sso` (`account.rb:8`), min password 8 (`user.rb:3`), first-run `FIRST_ROOM_NAME = "General"`. Personal settings under `resource :profile`/`notification_settings`/`push_subscriptions` (`user_id:"me"`); admin under `resource :account` → users/badges/bots/join_code/logo. Permissions from `user/role.rb` (`can_administer?`, `staff?`). Members already open to all (`accounts/users_controller.rb#index`; only update/destroy admin-gated). No dedicated `settings.css`/`account.css`/`auth.css` — auth uses the `session` layout + `signup.css` + shared inputs/buttons/panels.

**Gap & files:** mostly form + list re-skin against shared patterns (toggle, list row, destructive row, dialog, notice). The role-change **notice** ("X is now moderator") must match the existing controller flash wording — repeat server copy, don't invent. Add the staff-only **chip** in the settings surface. Consider carving `settings.css`/`auth.css` out of the shared files to keep the re-skin contained.

**Accent picker (C1) lands here** — the one net-new feature, placed where `/account` is already open: add `accent: "indigo"` to `Account`'s `has_json :settings` (`account.rb:18`), validate to the five values, and add the accent selector to community settings. `Account` is a **tenanted** model, so this is naturally per-workspace in SaaS and the single workspace when self-hosted; confirm `has_json` writes work under `activerecord-tenanted`.

**Commit boundary (PR 2):** auth · settings · members+CRUD · accent-picker, each its own commit.

---

### Step 6 — States (empty / loading / broken)

**v2 intent:** no-illustration empty states (heading + one sentence + CTA only where an action exists) across 11 surfaces; skeletons that mirror real geometry (room first-paint = 4 rows, older-messages spinner, optimistic in-flight message at 55% opacity, sidebar cold-start skeleton); recoverable failures stay in-surface as banners (connection-lost / message-failed-retry / room-gone / blocked-action / rate-limited); full-page errors for dead pages.

**Current state (verified):** `public/{400,404,406,422,500,502}.html` all exist. **Missing: 403 and offline.** 403s today are bare `head :forbidden` (`rooms_controller.rb:80,162`, `concerns/room_scoped.rb:29`) → browser's blank error. The PWA worker (`app/views/pwa/service_worker.js`) has a `fetch().catch(caches.match)` fallback but **nothing is ever precached**, so offline shows the browser's own error.

**Gap & files:**
- **New 403 page** — but note the current 403s are `head :forbidden` (no body) and one path *redirects* with flash `"Room not found or inaccessible"`. Decide per call site whether to render a styled 403 or keep the redirect. A `public/403.html` only helps if the controller actually renders a body — the `head :forbidden` sites need to render the page, not just set the status.
- **New offline page** — requires a service-worker **install/precache** step to cache a shell, then serve it on failed document fetch. This is a code change (worker + a cached offline document), not just a static file (handoff acknowledges this).
- Empty states: wire the no-illustration copy into each surface's existing empty partial (forum `_empty`, inbox per-controller empty config, etc.).
- Banners: connection-lost ties to AnyCable/HeartbeatChannel; message-failed to the composer; room-gone repeats the existing `"Room not found or inaccessible"` copy verbatim (server copy wins).
- 404/500 copy-replace; 406 keep-copy + name the supported browsers.

**Commit boundary (PR 2):** the states work as distinct commits — empty + banners, then 403 + offline (worker change).

---

## Part C — Cross-cutting

- **SaaS parity:** every token retirement and shadcn migration must sweep `saas/app/views` too (5 static pages already use shadcn utilities). Run **both** suites each step: `bin/rails test` and `SAAS=true bin/rails test saas/test/` (unset `UNTENANTED_DATABASE_URL` first for SaaS).
- **Avatars:** keep the app's avatar pipeline + upload; apply only v2's shape/size (36 square, radius 9). This touches `avatars.css` and ripples to every surface that renders an avatar.
- **Icons & fonts:** reuse/extend the app's existing inline-SVG icon set (don't import a new library). **Instrument Sans is confirmed (C4)** — self-host the woff2 (don't hotlink Google Fonts) and apply the v2 type scale with it. `docs/BRANDING.md` mandates no face today, so nothing is displaced; `CLAUDE.md`'s "system font stack" line updates when this lands. JetBrains Mono is spec-doc-only.
- **Verify UI changes fast with the system-test wall (do this every step).** The reskin changes DOM but must preserve the [Turbo](https://turbo.hotwired.dev/handbook/introduction) mechanics underneath — `<turbo-frame id>` targets, Turbo Stream `target` IDs, Turbo Drive navigation, and Stimulus `data-action` wiring. A browser-driven system test exercises those in a real browser and fails loudly on a broken frame ID or stream target that a CSS-only eye slides past. A reliable regression wall now exists — use it as the fast feedback loop, no manual clicking:
  - Tight loop (~20s, single-session): `bin/rails test test/system/{sidebar_navigation,message_composer,forum_browsing,inbox_surfaces,settings_and_membership,avatar_rendering,unread_rooms}_test.rb`
  - Full sweep (~100s, adds the multi-session real-time tests that confirm cross-client Turbo Streams still deliver): `bin/rails test test/system/`
  - The wall asserts behaviour through text/roles/stable BEM contracts, so it stays green through a faithful reskin and only reddens on a real regression. Cuprite (headless Chrome) drives it; `HEADLESS=0` to watch.
- **Test coverage before re-skinning behaviour:** the wall above covers navigation/rendering, but **not** the *new behaviours* Steps 2–3 introduce — the focus-within action-bar reveal, the "never shift the composer" reserved typing row, and the four-breakpoint sidebar rail (`message_formatter.js` is untested too). Write those tests first, per the tests-before-refactor rule — they're net-new authoring, not a checkbox.
- **Logical properties survive the reskin** — the mockups are LTR but the code is `inset-inline`/`padding-block`; keep it that way.
- **Hotwire Native webview:** the layout loads `native.css` when `hotwire_native_app?`, so verify each step's reskin inside the native wrapper too — not just the browser.
- **CLAUDE.md amendments — apply as each step *merges*, not up front.** CLAUDE.md describes the app as it is; don't flip it to the target state ahead of the code (and keep transient "mid-redesign" notes out of it — that's what this plan is for). The redesign invalidates these lines in the **Design Context** section; update each in the PR that makes it true:
  - **Typography** ("System font stack, 6-level size scale") → Instrument Sans UI face + the v2 type scale. Update with the Step 1 / typography change (C4).
  - **Color** ("Blues for interactive elements … Purple for contrast/emphasis") → Indigo as the default brand accent, five selectable accents, and `--color-contrast`/purple retired. Update with the Step 1 token change (C1).
  - **Design Principle 4** ("Mobile overlay sidebar, desktop docked sidebar") → still broadly true, but the desktop dock moves left with a rail/expanded/drawer state machine and a dark contrast treatment. Light-touch update with Step 2 (C2) if the wording now misleads.
  - **Theme** ("Light and dark mode via OKLch tokens") stays accurate — the token layer is consolidated, not replaced.

## Part D — Open decisions

Resolved by the owner (see Confirmed directions): ~~grouping~~ (C3, client-side), ~~type face~~ (C4, Instrument Sans), ~~sidebar~~ (C2, left+dark), ~~accent scope~~ (C1, build all five).

Still open:

1. **`body.library-collapsed`** — dormant "collapsed library" desktop mode: fully styled (~20 CSS selectors in `layout.css:26-62`, `sidebar.css:213-260`, `autocomplete.css:149-154`, `overrides.css:59-102`) and read by 3 guards in `toggle_class_controller.js:22,79,138`, but **never set anywhere** (no `classList.add`/`@body_class`/`<body class>`) — every rule unreachable, every guard always-false. Its CSS geometry is welded to the current right-side/120ch/70px shell (`translate(100%)` off the right, `26vw+70px`), all of which v2 replaces, so it can't be reused as the v2 drawer. **Recommend delete** the dead CSS + JS guards as a standalone zero-risk cleanup PR right before Step 2 (removing a never-set class can't change behavior), then build the v2 rail/expanded/drawer states as fresh explicit classes, keeping the controller's live `open`-class overlay/focus-trap logic. Alternative: revive it as the drawer — not recommended, since the geometry is rewritten either way and reviving welds v2 to legacy naming.
2. **403 handling** — Affects Step 6. **Mechanics gotcha:** `head :forbidden` is a normal 403 response, not a raised exception, so it **bypasses the exceptions app** — `public/403.html` would never be served. A styled 403 must be an **in-app render**, not a static file (and the states-doc copy is context-aware — "…for all 124 members" — which a static page can't interpolate anyway). There are ~15 `head :forbidden` sites in two families: **navigational/HTML** (admin/permission gates a human can hit via a stale link — `authorization.rb:8`, `room_scoped.rb:29`, `rooms_controller.rb:80,162`, `forum_post_scoped.rb:24`, `messages_controller.rb:50,75`, etc.) and **API/machine** (`api/bots/*`, bot-key `authentication.rb:203`, `sso/callbacks:19`) which must stay bare. A third pattern already exists and should stay: `rooms_controller.rb:55` `redirect_to root_url, alert: "Room not found or inaccessible"`. **Recommend:** add one `errors/forbidden` in-app view (app layout, context-aware copy) + a centralized `render_forbidden` helper (or `rescue_from` a `Forbidden` error) that **branches on format** — HTML → styled view, else `head :forbidden`; convert only the navigational gates. Leave API/bot/SSO bare and the room-access case as a redirect. (`head :too_many_requests` rate-limits are a separate concern — states doc handles them as a banner.)
3. **Inbox `notifications` + `messages` surfaces** — the handoff drew four inboxes; six exist. The two undrawn: **"All messages"** (`Inbox::MessagesQuery` unfiltered — firehose of every room you're in) and **"Notifications"** (same query, `involvement: :notifications_on` — firehose of rooms you closely follow; **distinct from Activity**, which is the `Notification`-record mention/boost/reply feed). Both are secondary today — reached from sidebar overflow menus (`_inbox_actions`/`_all_rooms_actions`, labels "Notifications"/"All messages") and rendered via `search_results_tag`. Decide: **(A, recommend)** keep both, re-skin via the shared search surface, keep them secondary in an overflow/"More" menu (out of the curated v2 tool block); **(B)** promote one into the v2 IA (needs designer spec); **(C)** retire them (a product removal — explicit call, not a silent omission). Flag their existence to the designer either way so promote/retire is deliberate.
4. ~~**D6 — accent selection: who sets it, and where?**~~ **Resolved (2026-08-12): workspace-level, stored in `account.settings`.** Admin picks one accent for the workspace, set under `/account` community settings; the layout emits `data-accent` on `:root` from that one source. **Persistence: add `accent: "indigo"` to the existing `has_json :settings` on `Account`** (`account.rb:18`) — no migration, matches the existing workspace-config pattern. Validate to the five allowed values in the model. **Do NOT reuse `custom_styles`** — that `text` column is retired freeform-CSS storage, is `ignored_columns` (`account.rb:5-6`), and is earmarked for a drop migration; reusing it is a type/naming mismatch and fights the rolling-deploy cleanup. Its drop can optionally ride along in the same PR as cleanup, but is a separate concern.
