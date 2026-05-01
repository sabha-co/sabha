---
title: "feat: Workspace database export for self-hosted migration"
type: feat
status: active
date: 2026-04-30
---

# feat: Workspace database export for self-hosted migration

## Overview

In SaaS mode, let a workspace administrator download their workspace's tenant SQLite database directly from the admin settings UI. The downloaded file is a structurally complete self-hosted Sabha database — drop it into a self-hosted install at `storage/production.sqlite3`, boot, and the workspace's rooms, messages, members, and history are all there. First login uses the existing email-OTP flow.

This unlocks a "you own your data, you can leave any time" guarantee for SaaS customers and gives admins a one-click migration path from managed Sabha to self-hosted.

---

## Problem Frame

Workspace admins on Sabha SaaS have no self-service way to take their data with them. The data already exists as a per-workspace SQLite file (`storage/workspaces/{env}/{tenant_id}/db/main.sqlite3`) and we have already verified it is structurally a drop-in for the self-hosted schema (84/84 migrations match, every table in `db/schema.rb` is present, FTS5 search index included). The only thing missing is a user-facing way to get the file off the server.

The existing `Workspace::Backup.create_from_database!` (`saas/app/models/workspace/backup.rb:23`) already does the hard part — `wal_checkpoint` plus a clean `SQLite3::Backup` copy — but it ships the result to R2 for operator-side cold archives, not to the admin's browser.

---

## Requirements Trace

- R1. A workspace administrator can download a fresh SQLite snapshot of their workspace from the admin UI.
- R2. The downloaded file is byte-equivalent to a clean copy of the live tenant DB after a WAL checkpoint, with no torn writes.
- R3. The endpoint is workspace-scoped and refuses non-administrators.
- R4. The feature is only present in SaaS mode; self-hosted installs do not see the button or expose the route.
- R5. Documentation explains the end-to-end migration path (download → place file → boot self-hosted → log in via email OTP).
- R6. The existing `Workspace::Backup` flow continues to work and reuses the same snapshot helper, so the two code paths can never drift.
- R7. Before the snapshot leaves the server, `users.workspace_membership_id` is cleared on every row. This column is a foreign key into the untenanted `workspace_memberships` table, which does not travel with the export; leaving it populated produces dangling references in the self-hosted DB.

---

## Scope Boundaries

- No file blob / Active Storage attachment migration. Avatars and message attachments will not appear on the self-hosted side. (Out of scope per explicit user direction.)
- No auth-state migration. `password_digest` is empty in the tenant DB; users re-authenticate on the self-hosted side via email OTP using the existing `AuthToken` flow. No `GlobalIdentity`/`GlobalSession` data is exported.
- No import-side tooling beyond a documented manual step. No `bin/rails sabha:import` task in this plan.
- No async / email-link delivery. v1 is a synchronous `send_data` download. Async with signed R2 URL is a follow-up if file sizes or proxy timeouts force the issue.
- No workspace-deletion-on-export semantics. The workspace continues to exist in SaaS after the download.

---

## Context & Research

### Relevant Code and Patterns

- `saas/app/models/workspace/backup.rb:23` — `Workspace::Backup.create_from_database!` already performs `PRAGMA wal_checkpoint(PASSIVE)` then `SQLite3::Backup.new(...).step(-1)` into a tempfile. The snapshot logic itself is what we want to reuse; the R2 upload is what we want to skip.
- `app/controllers/concerns/authorization.rb` — `ensure_administrator` is the standard gate for workspace-admin-only actions. Works in SaaS because `Current.user` is tenant-derived.
- `app/views/accounts/_admin_settings.html.erb` — the existing admin-only settings panel rendered inside `accounts/edit.html.erb`. Natural home for the download button.
- `config/routes.rb:54-78` — `resource :account` block with `scope module: "accounts"` is where workspace-admin-scoped resources live (badges, bots, custom_styles, join_code, logo, etc.). The new route follows this shape.
- `saas/config/routes.rb` — the SaaS engine's route file for SaaS-only routes. Workspace-context routes can be added inside the engine's tenant-scoped block.
- `saas/app/controllers/admin/workspace_backups_controller.rb` — example of an *operator*-side admin controller (untenanted, behind `ensure_superadmin`). Useful as a counterpoint, not a template — our controller is workspace-admin-side, not platform-admin-side.

### Institutional Learnings

- The recent `Defer SaaS Active Storage controller patching to on_load hook` commit confirms SaaS-only behavior is wired through engine initializers and on_load hooks. We follow the same pattern: feature is gated by SaaS being loaded, not by a runtime conditional in shared code.
- `Make bot event stream tenant-scoped to prevent cross-workspace leak` is a recent reminder that SaaS code that reads tenant data must be explicitly scoped. Our snapshot helper takes the tenant ID as an argument and never relies on ambient `Current.account`.

### External References

- None required. The implementation reuses an established SQLite backup pattern already proven inside this repo.

---

## Key Technical Decisions

- **Synchronous `send_data` for v1, not async + R2 link.** Rationale: simpler UX (one click → download), no email/notification surface needed, no R2 dependency for the user-facing flow. Workspaces are typically small. Pivot to async + signed link only if real workspace sizes or reverse-proxy timeouts force it.
- **Extract `Workspace.snapshot_tenant_to(tenant_id, dest_path)` as the single source of truth for snapshotting.** Both the existing `Workspace::Backup.create_from_database!` and the new export controller call it. Prevents drift between the operator-side backup and the admin-side export.
- **Controller lives in the SaaS engine** (`saas/app/controllers/accounts/database_exports_controller.rb`), routed from `saas/config/routes.rb`. The feature is SaaS-only by definition; placing it in the engine keeps self-hosted boot completely free of this code path.
- **`accounts/` namespace, not `admin/`.** This is a workspace-admin action (uses `Current.user.administrator?`), not a platform-superadmin action. Follows the same convention as `accounts/badges`, `accounts/bots`, etc.
- **Filename convention for the download:** `sabha-workspace-{external_id}-{YYYYMMDDHHMMSS}.sqlite3`. Includes external_id and timestamp so an admin who downloads twice can tell snapshots apart.
- **No new database table.** Unlike `Workspace::Backup`, exports are ephemeral — the file is streamed and the tempfile is reaped. We do not record export history in v1.
- **Sanitization happens in the export path, not the shared snapshot helper.** `users.workspace_membership_id` is cleared on the snapshot *after* `Workspace.snapshot_tenant_to` returns, before `send_data` runs. The operator-side `Workspace::Backup` flow keeps the column populated because those backups are restored back into the same SaaS instance where the untenanted `workspace_memberships` rows still exist. Putting the scrub inside the shared helper would silently break operator restores.

---

## Open Questions

### Resolved During Planning

- **Sync vs async download?** Sync via `send_data` for v1.
- **Where does the controller live?** SaaS engine, `accounts/` namespace.
- **How is the snapshot logic shared with `Workspace::Backup`?** Extracted into a `Workspace` class method; `Backup` is refactored to call it.
- **What auth gate?** Existing `ensure_administrator` from the main app's `Authorization` concern.
- **What about `password_digest` being empty?** Self-hosted side handles this via the existing email-OTP `AuthToken` flow. Documented in the migration guide; no code change needed.

### Deferred to Implementation

- Whether `send_data` needs `disposition: "attachment"` and `type: "application/vnd.sqlite3"` explicitly, or if Rails defaults are sufficient — verify during implementation.
- Tempfile cleanup mode: `Tempfile.create` with a block auto-unlinks, but `send_data` reads the data first so the block-scoped close is fine. Confirm during implementation that the streamed bytes are fully captured before the tempfile is unlinked.

---

## Implementation Units

- U1. **Extract snapshot helper from `Workspace::Backup`**

  **Goal:** Move the WAL-checkpoint + SQLite-backup-copy logic out of `Workspace::Backup.create_from_database!` and onto `Workspace` itself, so both the existing backup flow and the new export controller call one helper.

  **Requirements:** R2, R6.

  **Dependencies:** None.

  **Files:**
  - Modify: `saas/app/models/workspace.rb`
  - Modify: `saas/app/models/workspace/backup.rb`
  - Modify: `saas/test/models/workspace/backup_test.rb`
  - Test: `saas/test/models/workspace_test.rb` (new file if it does not already exist; add focused test for the snapshot helper)

  **Approach:**
  - Add a class method on `Workspace`, e.g. `Workspace.snapshot_tenant_to(tenant_id, dest_path)`, that runs `PRAGMA wal_checkpoint(PASSIVE)` inside `ApplicationRecord.with_tenant(tenant_id)`, opens the source SQLite at `storage/workspaces/{Rails.env}/{tenant_id}/db/main.sqlite3`, and writes a clean copy to `dest_path` via `SQLite3::Backup.new(dest, "main", source, "main").step(-1)`.
  - Refactor `Workspace::Backup.create_from_database!` to call the helper into its existing tempfile, then continue with the R2 upload and `Backup` row creation. The R2/upload responsibilities stay in `Workspace::Backup` — the helper only knows how to write a clean SQLite to a path.
  - Helper takes the tenant id as an argument; never reads ambient `Current.*` state. Important for the multi-tenant invariant.

  **Patterns to follow:**
  - Existing `with_tenant(...) { ApplicationRecord.connection.execute("PRAGMA wal_checkpoint(PASSIVE)") }` block in `saas/app/models/workspace/backup.rb:25-27`.
  - Existing `SQLite3::Backup` usage in the same file.

  **Test scenarios:**
  - Happy path: calling `Workspace.snapshot_tenant_to(tenant_id, path)` writes a non-empty SQLite file at `path` whose `users` / `rooms` / `messages` row counts match the live tenant DB.
  - Happy path: opening the snapshot with `SQLite3::Database.new` and querying `schema_migrations.version` returns the same set of versions as the live tenant DB.
  - Happy path: the helper preserves `users.workspace_membership_id` exactly as it appears in the live tenant DB. (Sanitization is the export controller's responsibility; the shared helper must not mutate the snapshot, since `Workspace::Backup` relies on a faithful copy.)
  - Edge case: when called for a workspace with zero messages, the snapshot is still a valid SQLite file with the expected empty tables and full schema.
  - Integration: `Workspace::Backup.create_from_database!` still produces a working backup row + R2 object after the refactor (existing backup test still passes; extend it if needed to assert the helper is invoked).

  **Verification:**
  - The existing `Workspace::Backup` test suite passes unchanged.
  - The new helper has direct test coverage that does not depend on R2 being configured.

- U2. **Add the workspace database export controller and route**

  **Goal:** Expose a workspace-admin endpoint that snapshots the current workspace's tenant DB, scrubs untenanted FKs from the snapshot, and streams it to the admin's browser as an attachment.

  **Requirements:** R1, R2, R3, R4, R7.

  **Dependencies:** U1.

  **Files:**
  - Create: `saas/app/controllers/accounts/database_exports_controller.rb`
  - Modify: `saas/config/routes.rb`
  - Test: `saas/test/controllers/accounts/database_exports_controller_test.rb`

  **Approach:**
  - Controller `Accounts::DatabaseExportsController < ApplicationController` with a single `#create` action (POST). Use POST so the action is non-idempotent and avoids GET-prefetch surprises.
  - `before_action :ensure_administrator` from the main app's `Authorization` concern. `head :forbidden` for non-admins.
  - In the action:
    1. Open `Tempfile.create(["workspace-export", ".sqlite3"])`.
    2. Call `Workspace.snapshot_tenant_to(ApplicationRecord.current_tenant, tempfile.path)`.
    3. Sanitize the snapshot: open it with `SQLite3::Database.new(tempfile.path)` and run `UPDATE users SET workspace_membership_id = NULL`. Close the connection.
    4. `send_data File.binread(tempfile.path), filename: "sabha-workspace-#{ApplicationRecord.current_tenant}-#{Time.current.strftime("%Y%m%d%H%M%S")}.sqlite3", type: "application/vnd.sqlite3", disposition: "attachment"`.
  - Keep the sanitization step inline in the controller for now. If more columns or tables ever need scrubbing, promote it to `Workspace.sanitize_export!(path)` in a follow-up.
  - Route: inside `saas/config/routes.rb`, in the workspace-scoped block (the same block that hosts other tenant-context routes), add `resource :database_export, only: :create, controller: "accounts/database_exports"` nested under `resource :account` if that nesting exists in the engine; otherwise mirror the main app's `resource :account` shape inside the engine routes file.

  **Patterns to follow:**
  - Auth gate: `app/controllers/concerns/authorization.rb` — `ensure_administrator`.
  - Single-action workspace-admin controller: `app/controllers/accounts/join_codes_controller.rb` (similar shape — one POST, admin-only, scoped to the account/workspace).
  - SaaS-only route registration: pattern already used elsewhere in `saas/config/routes.rb`.

  **Test scenarios:**
  - Happy path: signed in as a workspace administrator, POST to the export endpoint returns 200 with `Content-Disposition: attachment` and a `.sqlite3` filename. Body is non-empty and parses as a valid SQLite database.
  - Happy path: the streamed bytes, written to disk and queried, contain the workspace's users and messages.
  - Happy path / R7: opening the streamed snapshot, every row in `users` has `workspace_membership_id IS NULL`, even if the live tenant DB had non-null values for those rows before the export.
  - Error path: signed in as a non-admin member, POST returns 403 / forbidden.
  - Error path: signed out, POST redirects to login (or returns 401 — match whatever `ApplicationController` already does).
  - Edge case: when the workspace has had recent writes, the snapshot reflects them (i.e., the WAL checkpoint actually ran). Insert a message, hit the endpoint, verify the message is in the downloaded file.
  - Integration: route only resolves under a workspace-scoped path (e.g., `/{external_id}/account/database_export`) and not at top-level SaaS paths.

  **Verification:**
  - Manual: log in as an admin in dev, click the button (after U3), and the browser downloads a `.sqlite3` file. Open it with `sqlite3` and confirm tables.
  - Manual: rename the downloaded file to `storage/development.sqlite3` in a fresh self-hosted checkout, run the server, log in via email OTP, see the workspace's rooms and messages.

- U3. **Add the "Download workspace database" button to admin settings**

  **Goal:** Expose the export action in the workspace admin settings UI, visible only to administrators in SaaS mode.

  **Requirements:** R1, R3, R4.

  **Dependencies:** U2.

  **Files:**
  - Modify: `app/views/accounts/_admin_settings.html.erb`

  **Approach:**
  - Add a new section to `_admin_settings.html.erb` titled something like "Export workspace data" with a short explanation: "Download a SQLite snapshot of this workspace. You can use it to run Sabha on your own server."
  - Render a `button_to` that POSTs to the new route. Use a simple anchor-styled button matching existing admin settings buttons in the same partial.
  - Wrap the section in a SaaS-mode guard so it does not appear in self-hosted installs. Use the same conditional pattern the rest of the codebase uses for SaaS-only UI (check whether `defined?(Saas)` / `Rails.application.config.saas_enabled` / similar — confirm the canonical check during implementation; do not invent a new one).
  - Below the button, add small print noting the caveats: file attachments are not included; users will need to sign in again via email on the self-hosted instance.

  **Patterns to follow:**
  - Existing admin-only blocks inside `_admin_settings.html.erb` and `accounts/edit.html.erb` (the `if Current.user.administrator?` and `if Current.user.can_administer?` guards).
  - Existing `button_to` usage in workspace settings views (search for examples of POST buttons in `app/views/accounts/`).

  **Test scenarios:**
  - Test expectation: none — view-only change. Manual verification covers it.

  **Verification:**
  - Manual: in SaaS mode, the button renders inside `/account/edit` for an admin and is absent for non-admins.
  - Manual: in self-hosted mode, the section is not present.
  - Clicking the button initiates a `.sqlite3` download.

- U4. **Self-host migration documentation**

  **Goal:** Document the end-to-end migration: how to download the SQLite from the SaaS admin UI, where to drop it on a self-hosted Sabha install, how first login works, and what does and does not come along.

  **Requirements:** R5.

  **Dependencies:** U3 (for accurate UI references).

  **Files:**
  - Create: `docs/multi-tenant/self-host-migration.md`
  - Modify: `docs/multi-tenant/ARCHITECTURE.md` or a top-level index in `docs/multi-tenant/` to link to the new guide (only if such an index exists).

  **Approach:**
  - Sections to cover:
    1. **What this gives you and what it doesn't.** Includes everything in your tenant DB: users, rooms, messages, threads, search index, bookmarks, badges, bans, blocks, webhooks, push subscriptions. Does not include: file attachments / avatars / Active Storage blobs; SaaS auth state — every user re-authenticates via email on the self-hosted instance. Note that `users.workspace_membership_id` is cleared in the export so there are no dangling references to SaaS-only tables.
    2. **How to download.** Account settings → "Export workspace data" → "Download workspace database". You get a `sabha-workspace-{id}-{timestamp}.sqlite3` file.
    3. **How to boot self-hosted with it.** Stand up a fresh self-hosted Sabha checkout per the standard self-hosted setup. Replace `storage/{Rails.env}.sqlite3` with the downloaded file (renaming as needed). Boot the server.
    4. **First login.** Use "email me a sign-in link" on the self-hosted login page. Sign in as the workspace administrator (whoever had the admin role in SaaS retains it). Re-invite or notify members so they can do the same.
    5. **Caveats and known gaps.** Avatars / message attachments will be missing or broken — they refer to blobs that didn't come along. Old auth tokens and sessions are dead. Any operator-side state (Workspace registry, GlobalIdentity rows) does not move.
  - Keep the doc terse and operational. No marketing fluff. Cross-link from the SaaS architecture doc if useful.

  **Patterns to follow:**
  - Existing tone and structure of `docs/multi-tenant/DEPLOYMENT.md` and `docs/multi-tenant/DEVELOPMENT.md`.

  **Test scenarios:**
  - Test expectation: none — documentation only.

  **Verification:**
  - Doc renders cleanly in GitHub Markdown preview.
  - The procedure described in the doc actually works when followed against a real export (validated as part of U2's manual verification).

---

## System-Wide Impact

- **Interaction graph:** New endpoint sits behind workspace-admin auth and reads from the per-workspace SQLite. No write path. No callbacks, jobs, or broadcasts triggered by the export.
- **Error propagation:** A failed snapshot raises an exception inside `send_data`'s setup; controller can let the standard 500 handler take it. No partial download is possible because `send_data` only fires after the tempfile is written.
- **State lifecycle risks:** Tempfile must be cleaned up. `Tempfile.create` with a block handles this; using `File.binread` inside the block is safe because `send_data` copies bytes into the response before returning.
- **API surface parity:** None — this is a new endpoint with no existing surface to maintain compatibility with.
- **Integration coverage:** The U1 helper is exercised by both `Workspace::Backup` and the new controller; one integration-level controller test plus the existing backup test prove they share the same code path.
- **Unchanged invariants:** `Workspace::Backup` external behavior (R2 key shape, retention, `Backup` row creation) is unchanged. The R2 backup workflow continues to work for operators.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Reverse proxy / load balancer times out on large synchronous downloads. | Workspaces in current usage are small. If real-world sizes exceed comfort, follow-up plan switches to async + signed R2 link reusing the existing `Workspace::Backup` flow. |
| Tempfile is read into memory via `File.binread`, which could spike RSS for very large DBs. | Acceptable for v1 given current workspace sizes. Switch to streaming `send_file` against the tempfile path if memory becomes an issue. |
| Concurrent writes during the snapshot produce a torn DB. | `PRAGMA wal_checkpoint(PASSIVE)` plus `SQLite3::Backup.step(-1)` is the standard safe-snapshot pattern and is already proven by the existing `Workspace::Backup` flow. |
| Admin downloads the file and uses it to spin up a competing instance while still paying SaaS — no business-side concern, this is the explicit goal of the feature. | Documented as a feature, not a leak. |
| User confusion when avatars / attachments are missing on the self-hosted side. | Surfaced in the UI small print under the button and in `docs/multi-tenant/self-host-migration.md`. |
| Helper extraction subtly breaks `Workspace::Backup` (e.g., the snapshot file is opened but not closed, and the R2 upload reads zero bytes). | U1 keeps the existing backup test green and adds direct coverage for the helper. Manual smoke of operator backup before merge. |

---

## Documentation / Operational Notes

- New user-facing doc: `docs/multi-tenant/self-host-migration.md`.
- No new env vars, monitoring, or alerts needed in v1.
- No data migration required; the feature is purely additive.
- Operators should be aware that admin-triggered exports are now possible — note in `docs/multi-tenant/DEPLOYMENT.md` if there is an "operator-visible behaviors" section, otherwise leave alone.

---

## Sources & References

- Verified DB compatibility analysis (this conversation, 2026-04-30): 84/84 migrations match between tenant SQLite and `db/migrate/`; all `db/schema.rb` tables present in tenant DB; `users.role` populated; `password_digest` empty by design.
- Existing snapshot pattern: `saas/app/models/workspace/backup.rb:23-46`.
- Authorization concern: `app/controllers/concerns/authorization.rb`.
- Admin settings UI partial: `app/views/accounts/_admin_settings.html.erb`.
- Recent SaaS architecture commits: `1e168e2` (tenant-scoped bot event stream), `d6d417c` (deferred Active Storage controller patching) — confirm SaaS-only logic stays inside the engine and uses on_load hooks.
