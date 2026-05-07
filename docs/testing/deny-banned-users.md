# Manual testing: deny banned/deactivated workspace users

Branch: `deny-banned-workspace-users`

This branch:
- **SaaS:** mirrors `User#active?` onto `workspace_memberships.user_active` so the workspace selector and `/settings` can filter without crossing tenants.
- **SaaS:** denies banned/deactivated users at session resume and bounces them to `/settings?denied=workspace`, where a persistent banner explains the redirect. The settings list shows "Inactive" for any membership where the user lost access.
- **Both modes:** sends an email notification when a user is banned and another when unbanned.
- **SaaS:** drops the `user_active` mirror to `false` when a workspace User is hard-destroyed; restores to `true` on rejoin.

Verify both modes — most behavior is SaaS-only, but self-hosted gets a regression sweep plus the new mailer.

---

## Self-hosted

The mirror is gated on `Sabha.saas?`. The mailer is not — ban/unban emails fire in both modes.

### Setup

```bash
bin/rails saas:disable && bundle install   # only if SAAS was previously enabled
bin/setup
bin/dev
```

Visit http://localhost:3000 and create the first admin via the welcome flow.

### Scenarios

**SH-1. Admin bans a member**

1. Sign in as admin. Invite a second user, sign them in (separate browser).
2. As admin, visit the second user's profile and click **Ban**.
3. Sign back in as the banned user (or refresh their tab).

   *Expected:*
   - Banned user is logged out / cannot post / sees the banned state. ActionCable disconnects.
   - **One ban-notification email is enqueued** to the banned user (subject: "Your access to … has been suspended"). Confirm in `letter_opener` or by tailing logs for `UserMailer#banned`.

**SH-2. Admin unbans the member**

1. Continuing from SH-1, as admin click **Unban** on the banned user's profile.
2. Banned user signs in again.

   *Expected:*
   - Full access restored.
   - **One unban-notification email is enqueued** (subject: "Your access to … has been restored").

**SH-3. User leaves the workspace (deactivate)**

1. Sign in as a non-admin member.
2. Settings → leave workspace.

   *Expected:*
   - User is signed out, status becomes `deactivated`, direct rooms still appear for other members but the user can't post.
   - **No email is sent** (only ban/unban transitions email; deactivate/reactivate do not).

**SH-4. Reactivate a deactivated user (admin)**

1. As admin, find the deactivated user and reactivate via the user profile.

   *Expected:*
   - User can sign in again.
   - **No email** — only `banned → active` triggers the unban mailer; `deactivated → active` is silent.

**SH-5. User hard-destroy via console**

In a separate terminal:
```bash
bin/rails console
> u = User.find_by(email_address: "test@example.com")
> u.destroy!
```

   *Expected:* no errors. Messages from this user are deleted, memberships cleaned, no FK violations. No email sent.

**SH-6. Sanity: no `workspace_memberships` writes**

Self-hosted has no `WorkspaceMembership` table. Confirm no errors mentioning `workspace_memberships` in the dev log during any of SH-1 through SH-5.

```bash
grep -i workspace_membership log/development.log
```

   *Expected:* no output.

---

## SaaS

This is where the new redirect, banner, and selector-filtering behavior lives. You'll need at least 2 GlobalIdentities and 2 workspaces.

### Setup

```bash
bin/rails saas:enable && bundle install && bin/rails saas:setup
bin/dev
```

Visit http://localhost:3000. Sign up via `/registration/new` for the first identity, create a workspace ("Acme"). Open a second browser (or incognito) and register a second identity, create a second workspace ("Beta") OR have it join Acme via an invite.

OTP codes for sign-in: tail `log/development.log` for the magic link / code, or check `letter_opener` if enabled.

### Backfill the mirror (one-time, post-migration)

The new `workspace_memberships.user_active` column defaults to `true`, so memberships created **before** the migration ran will all be `true` — even when the per-tenant User is already banned/deactivated. Run the backfill once to repair existing data:

```bash
unset UNTENANTED_DATABASE_URL    # only if it's pointing at the test DB
SAAS=true bin/rails workspace_membership:backfill_user_active
```

The task reads each tenant's `User.status` and flips `user_active=false` for any membership where the User is banned/deactivated. Output looks like:

```
Marked inactive: tenant=1000007 user_id=259 status=deactivated
Marked inactive: tenant=1000006 user_id=511 status=deactivated
...
Done. Flipped 81 membership(s) to inactive. Skipped 0.
```

The same step is required in **production** after deploying this branch — without it, the workspace selector and `/settings` will keep surfacing inactive memberships until each User has a fresh status change. Add to the deploy runbook.

The task writes only to `workspace_memberships` (via `update_column`) and **does not trigger the ban/unban mailer** — no emails are sent during backfill, even if it flips state for thousands of memberships.

### Helpful console snippets

```ruby
# Inspect the mirror state
WorkspaceMembership.all.pluck(:tenant, :global_identity_id, :user_id, :user_active)

# Ban a user inside a tenant
ApplicationRecord.with_tenant("1000001") { User.find(1).ban }

# Force a stale mirror (drift case)
WorkspaceMembership.find(N).update_column(:user_active, true)
```

`unset UNTENANTED_DATABASE_URL` before running console if it complains about Postgres.

---

### A. Mirror updates (untenanted Postgres ← tenanted SQLite)

**SaaS-1. Ban flips `user_active` to false**

1. Sign in as Acme admin.
2. From a separate session, sign in a member ("Bob"). Confirm Bob can read messages.
3. As admin, ban Bob from his profile page.
4. In console:

   ```ruby
   WorkspaceMembership.find_by(global_identity: GlobalIdentity.find_by(email_address: "bob@..."), tenant: "1000001").user_active
   ```

   *Expected:* `false`. **One ban email enqueued** to Bob.

**SaaS-2. Unban restores `user_active` to true**

1. Continuing: admin unbans Bob.
2. Re-check the same query.

   *Expected:* `true`. **One unban email enqueued** to Bob.

**SaaS-3. Leave workspace flips `user_active` to false**

1. Bob (signed in) navigates to the Acme workspace settings and leaves the workspace.
2. Re-check `user_active` for Bob's Acme membership.

   *Expected:* `false`. The membership row is preserved (so staff admin can still see the user). **No email** (deactivate doesn't email).

**SaaS-4. Rejoin restores `user_active` to true**

1. Bob revisits a fresh invite link for Acme and joins.
2. Re-check.

   *Expected:* `true`. No email.

**SaaS-5. Hard-destroy flips `user_active` to false AND clears `user_id`**

1. In console:

   ```ruby
   ApplicationRecord.with_tenant("1000001") do
     User.find_by(email_address: "bob@...").destroy!
   end
   ```

2. Inspect the membership.

   *Expected:* `user_id: nil`, `user_active: false`. No email.

**SaaS-6. Re-sign-in after destroy restores both**

1. Bob signs back into Acme via a join link or the workspace selector (existing membership row).
2. Inspect the membership.

   *Expected:* `user_id` is set to a new value, `user_active: true`. Bob has access.

---

### B. Auth-time redirect to `/settings`

The deny guard always redirects to `/settings?denied=workspace` regardless of how many other workspaces the user has. The destination is intentional: it shows the user their full workspace list (with "Inactive" labels) and avoids redirect-chain flash issues.

**SaaS-7. Banned user is bounced to /settings**

1. Admin bans Bob in Acme. (Bob may have other workspaces or not — doesn't matter.)
2. Bob refreshes any Acme URL (e.g. `/1000001/`).

   *Expected:*
   - Redirect to `/settings?denied=workspace`.
   - **Persistent red banner** at the top of the page: "You no longer have access to that workspace."
   - The banner does NOT auto-fade. Refresh keeps it (the query param is in the URL). It clears when the user clicks any link to `/settings` without the param.

**SaaS-8. Deactivated user (left workspace) is also bounced to /settings**

1. Bob leaves Acme.
2. Bob refreshes any Acme URL.

   *Expected:* same as SaaS-7 — `/settings?denied=workspace` with the banner.

**SaaS-9. Drift case fail-closes**

The mirror is a hint, not a security control. The auth guard reads the tenanted `User` row.

1. Admin bans Bob in Acme.
2. In console, manually corrupt the mirror:

   ```ruby
   WorkspaceMembership.find_by(global_identity: GlobalIdentity.find_by(email_address: "bob@..."), tenant: "1000001").update_column(:user_active, true)
   ```

3. Bob reloads an Acme URL.

   *Expected:* still bounced to `/settings?denied=workspace`. The auth guard reads `User#banned?` from SQLite and ignores the stale mirror.

---

### C. Workspace selector & settings list

**SaaS-10. Banned workspace is hidden from the sidebar**

1. Bob is a member of Acme + Beta. Bob is signed in on Beta.
2. Admin bans Bob in Acme.
3. Bob reloads Beta.

   *Expected:* sidebar shows Beta only — no Acme.

**SaaS-11. Banned workspace shows on `/settings` with "Inactive" label**

1. Continuing: Bob navigates to `/settings`.

   *Expected:*
   - All workspaces Bob has memberships in are listed.
   - For Acme (banned), the role label reads **"Inactive"** (where active workspaces show "Member" or "Administrator").
   - Clicking the Acme row attempts to navigate to its tenanted settings → bounces back to `/settings?denied=workspace` (the deny guard catches it).

**SaaS-12. `/workspaces` redirect skips banned workspaces**

1. Same setup as SaaS-10.
2. Bob navigates to `/workspaces` directly.

   *Expected:* redirects to Beta (the only active workspace). Acme is not picked.

---

### D. Drift / defense-in-depth

**SaaS-13. Mirror write failure doesn't roll back the ban**

Hard to reproduce manually — covered by `WorkspaceMembershipTest#test_mirror_write_failure_logs_and_does_not_roll_back_the_User#deactivate_transaction`. Skip unless you're specifically suspicious.

---

### E. Join flow

**SaaS-14. Banned member visiting a join URL is redirected away**

1. Bob is banned from Acme. Acme has an active invite link (e.g. `/1000001/join/ABC123`).
2. Bob visits the join URL while signed in.

   *Expected:* redirected to `/settings?denied=workspace` — NOT into Acme.

---

### F. Cross-session / multi-tab

**SaaS-15. Active session gets kicked on next request after ban**

1. Bob is signed in and active on Acme in browser tab 1.
2. Admin bans Bob in browser tab 2.
3. Bob clicks any link in tab 1 (no full reload).

   *Expected:*
   - Bob is redirected to `/settings?denied=workspace`.
   - ActionCable disconnects (existing behavior — see `app/channels/application_cable/connection.rb`).
   - **Ban-notification email** also enqueued (from step 2's admin action).

---

### G. Email notifications

**SaaS-16. Ban triggers exactly one email per ban transition**

1. Admin bans Bob in Acme.

   *Expected:* exactly one email enqueued via `UserMailer#banned`. Subject: "Your access to {Acme account name} has been suspended".

2. Admin unbans Bob.

   *Expected:* exactly one email enqueued via `UserMailer#unbanned`. Subject: "Your access to {Acme account name} has been restored".

**SaaS-17. Other lifecycle transitions do NOT email**

1. Bob leaves a workspace (deactivate).
2. Bob rejoins via invite (deactivated → active).
3. A user gets hard-destroyed.

   *Expected:* no `UserMailer#banned` or `UserMailer#unbanned` mail enqueued for any of these.

**SaaS-18. Bots and emailless users don't trigger mail**

1. Ban a bot user (if you have one set up).

   *Expected:* no email enqueued (the callback short-circuits on `bot?`).

---

## Sign-off checklist

- [ ] Self-hosted: SH-1 through SH-6 pass; ban/unban emails arrive; no `workspace_memberships` writes in log
- [ ] SaaS Mirror (A): SaaS-1 through SaaS-6 pass; column matches User state in every case
- [ ] SaaS Redirect (B): SaaS-7 through SaaS-9 pass; banner is persistent and doesn't auto-fade
- [ ] SaaS Selector & Settings list (C): SaaS-10 through SaaS-12; banned workspace hidden from sidebar, "Inactive" label on /settings
- [ ] SaaS Drift (D): SaaS-13 covered by automated test
- [ ] SaaS Join (E): SaaS-14 redirects to `/settings?denied=workspace`
- [ ] SaaS Multi-tab (F): SaaS-15 kicks active session on next request, ban email arrives
- [ ] SaaS Mailer (G): SaaS-16 sends exactly one email per ban/unban; SaaS-17 confirms other transitions are silent; SaaS-18 confirms bot/emailless users are skipped
