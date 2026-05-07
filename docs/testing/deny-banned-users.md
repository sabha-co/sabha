# Manual testing: deny banned/deactivated workspace users

Branch: `deny-banned-workspace-users`

This branch:
- Mirrors `User#active?` onto `workspace_memberships.user_active` (SaaS) so the workspace selector can filter without crossing tenants.
- Denies banned/deactivated users at session resume in SaaS, redirecting to the next available workspace (or `/workspaces/new`).
- Drops the orphan `user_active` row when a User is hard-destroyed; restores it on rejoin.

Verify both modes — most behavior is SaaS-only, but self-hosted gets an audit pass to confirm no regressions.

---

## Self-hosted

The mirror callback is gated on `Sabha.saas?`, so all User lifecycle changes should behave exactly as before. This section is a regression sweep.

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

   *Expected:* banned user is logged out / cannot post / sees the banned state. ActionCable disconnects.

**SH-2. Admin unbans the member**

1. Continuing from SH-1, as admin click **Unban** on the banned user's profile.
2. Banned user signs in again.

   *Expected:* full access restored.

**SH-3. User leaves the workspace (deactivate)**

1. Sign in as a non-admin member.
2. Settings → leave workspace.

   *Expected:* user is signed out, status becomes `deactivated`, direct rooms still appear for other members but the user can't post.

**SH-4. User hard-destroy via console**

In a separate terminal:
```bash
bin/rails console
> u = User.find_by(email_address: "test@example.com")
> u.destroy!
```

   *Expected:* no errors. Messages from this user are deleted, memberships cleaned, no FK violations.

**SH-5. Sanity: no `workspace_memberships` writes**

Self-hosted has no `WorkspaceMembership` table. Confirm no errors mentioning `workspace_memberships` in the dev log during any of SH-1 through SH-4.

```bash
grep -i workspace_membership log/development.log
```

   *Expected:* no output.

---

## SaaS

This is where the real behavior lives. You'll need at least 2 GlobalIdentities and 2 workspaces.

### Setup

```bash
bin/rails saas:enable && bundle install && bin/rails saas:setup
bin/dev
```

Visit http://localhost:3000. Sign up via `/registration/new` for the first identity, create a workspace ("Acme"). Open a second browser (or incognito) and register a second identity, create a second workspace ("Beta") OR have it join Acme via an invite.

OTP codes for sign-in: tail `log/development.log` for the magic link / code, or check `letter_opener` if enabled.

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

   *Expected:* `false`.

**SaaS-2. Unban restores `user_active` to true**

1. Continuing: admin unbans Bob.
2. Re-check the same SQL/console query.

   *Expected:* `true`.

**SaaS-3. Leave workspace flips `user_active` to false**

1. Bob (signed in) navigates to the Acme workspace settings and leaves the workspace.
2. Re-check `user_active` for Bob's Acme membership.

   *Expected:* `false`. The membership row is preserved (so staff admin can still see the user).

**SaaS-4. Rejoin restores `user_active` to true**

1. Bob revisits a fresh invite link for Acme and joins.
2. Re-check.

   *Expected:* `true`.

**SaaS-5. Hard-destroy flips `user_active` to false AND clears `user_id`**

1. In console:

   ```ruby
   ApplicationRecord.with_tenant("1000001") do
     User.find_by(email_address: "bob@...").destroy!
   end
   ```

2. Inspect the membership.

   *Expected:* `user_id: nil`, `user_active: false`.

**SaaS-6. Re-sign-in after destroy restores both**

1. Bob signs back into Acme via a join link or the workspace selector (existing membership row).
2. Inspect the membership.

   *Expected:* `user_id` is set to a new value, `user_active: true`. Bob has access.

---

### B. Auth-time redirect

**SaaS-7. Banned user with one workspace lands on `/workspaces/new`**

1. Admin bans Bob in Acme. Bob has no other workspaces.
2. Bob refreshes any Acme URL (e.g. `/1000001/`).

   *Expected:* redirected directly to `/workspaces/new`. Page shows "You're not part of any workspace yet" and an alert: "You no longer have access to this workspace." No transit through `/workspaces`.

**SaaS-8. Banned user with another workspace lands on the next workspace**

1. Bob is a member of both Acme and Beta. Admin bans Bob in Acme.
2. Bob refreshes an Acme URL.

   *Expected:* redirected directly to `/{Beta_external_id}` (Beta's root). Alert: "You no longer have access to this workspace."

**SaaS-9. Deactivated user (left workspace) is treated like banned**

1. Bob leaves Acme. He still has access to Beta.
2. Bob refreshes an Acme URL.

   *Expected:* redirected to Beta. Same alert.

**SaaS-10. Deactivated user with no other workspaces lands on `/workspaces/new`**

1. Bob leaves his only workspace.
2. Bob refreshes the Acme URL (or the URL he had open).

   *Expected:* `/workspaces/new`.

---

### C. Workspace selector / sidebar

**SaaS-11. Banned workspace is hidden from the sidebar**

1. Bob is a member of Acme + Beta. Bob is signed in and on Beta's root page.
2. Admin bans Bob in Acme.
3. Bob reloads Beta.

   *Expected:* the sidebar workspace selector shows Beta only — no link to Acme.

**SaaS-12. Banned workspace is hidden from `/workspaces`**

1. Same as SaaS-11.
2. Bob navigates to `/workspaces` directly.

   *Expected:* redirects to Beta (the only active workspace), not Acme.

---

### D. Drift / defense-in-depth

**SaaS-13. Stale `user_active=true` doesn't bypass the auth guard**

The mirror is a hint for the selector, not a security control. The auth guard reads the tenanted `User` row.

1. Admin bans Bob in Acme.
2. In console, manually corrupt the mirror:

   ```ruby
   WorkspaceMembership.find_by(global_identity: GlobalIdentity.find_by(email_address: "bob@..."), tenant: "1000001").update_column(:user_active, true)
   ```

3. Bob reloads an Acme URL.

   *Expected:* still gets bounced — auth guard reads `User#banned?` from SQLite and redirects. Alert shows.

**SaaS-14. Mirror write failure doesn't roll back the ban**

This is harder to reproduce manually — it's covered by `WorkspaceMembershipTest#test_mirror_write_failure_logs_and_does_not_roll_back_the_User#deactivate_transaction`. Skip unless you're specifically suspicious.

---

### E. Join flow

**SaaS-15. Banned member visiting a join URL is redirected away**

1. Bob is banned from Acme. Acme has an active invite link (e.g. `/1000001/join/ABC123`).
2. Bob visits the join URL while signed in.

   *Expected:* Bob is redirected — NOT into Acme. Lands on Beta (if he's a member) or `/workspaces/new`. Alert: "You no longer have access to this workspace."

---

### F. Cross-session / multi-tab

**SaaS-16. Active session gets kicked on next request after ban**

1. Bob is signed in and active on Acme in browser tab 1.
2. Admin bans Bob in browser tab 2.
3. Bob clicks any link in tab 1 (no full reload).

   *Expected:* Bob is redirected to next workspace or `/workspaces/new`. ActionCable disconnects (existing behavior — see `app/channels/application_cable/connection.rb`).

---

## Sign-off checklist

- [ ] Self-hosted: SH-1 through SH-5 pass; no `workspace_memberships` writes in log
- [ ] SaaS Mirror (A): SaaS-1 through SaaS-6 pass; column matches User state in every case
- [ ] SaaS Redirect (B): SaaS-7 through SaaS-10 pass; no double-redirect through `/workspaces`
- [ ] SaaS Sidebar (C): SaaS-11, SaaS-12 pass; banned workspace never linked
- [ ] SaaS Drift (D): SaaS-13 still denies access despite stale mirror
- [ ] SaaS Join (E): SaaS-15 redirects away from banned workspace
- [ ] SaaS Multi-tab (F): SaaS-16 kicks active session on next request
