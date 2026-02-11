# GlobalIdentity ↔ User Sync Behavior

GlobalIdentity (untenanted PostgreSQL) and User (tenanted SQLite per-workspace) live in separate databases. They cannot share transactions. This document describes how data flows between them and the edge cases to be aware of.

## Data Ownership

| Field | Owner | Sync Direction | Notes |
|-------|-------|---------------|-------|
| **email** | GlobalIdentity | Global → Tenant | Readonly at tenant level in SaaS mode |
| **name** | User (per-workspace) | Tenant → Global | GlobalIdentity.name is the default for new workspace joins |

## Email

**Owned globally.** Users edit their email on the global settings page (`/settings`). The change triggers OTP re-verification via `GlobalIdentity#initiate_email_change!`.

**Global → Tenant sync:** After email is confirmed, `GlobalIdentity#sync_email_to_workspaces` pushes the new email to all workspace User records via `update_column`. This iterates active `workspace_memberships`.

**Tenant → Global:** Blocked. The email field is disabled/readonly on the workspace profile page in SaaS mode (`profiles/show.html.erb`).

## Name

**Owned per-workspace.** Users edit their name on the workspace profile page. Each workspace can have a different display name.

**Tenant → Global sync:** When `User.name` changes, the `sync_name_to_global_identity` callback writes the new name back to `GlobalIdentity.name`. This is best-effort — failures (e.g. PostgreSQL connectivity issues) are rescued and logged, so a global DB outage won't roll back the tenant-side User update.

**Global → Tenant:** No sync. Changing your name in workspace A does not change it in workspace B. The GlobalIdentity name is only used as a **default** when creating a new User record in a workspace.

**Registration:** The SaaS registration form collects the name and stores it on GlobalIdentity. The HTML form has `required: true` but the model does not enforce presence — name is optional at the model level. If blank, workspace User creation falls back to `email.split("@").first.titleize`.

## Fallback Chain for User Name

When a User record is created in a workspace (via `WorkspaceMembership#create_user!` or `Workspace.create_with_database!`), the name is resolved as:

```ruby
name || global_identity.name || global_identity.email_address.split("@").first.titleize
```

1. Explicit `name` parameter (if passed to `create_user!`)
2. `GlobalIdentity.name` (from registration or last workspace name change)
3. Email prefix, titleized (last resort)

## Edge Case: Leave + Rejoin

When a user leaves a workspace:
1. Their `User` record is **deactivated** (soft delete, messages preserved)
2. Their `WorkspaceMembership` is **destroyed**

When they rejoin, `create_user!` looks up the deactivated User by `global_identity.email_address`. If found, it reactivates them with their original workspace data.

**Known limitation:** If the user changed their email on GlobalIdentity _after_ leaving (and therefore after the WorkspaceMembership was destroyed), `sync_email_to_workspaces` cannot reach the deactivated User. On rejoin, the lookup by new email won't find the old User record, resulting in a new User being created instead of reactivating the old one. This is an accepted edge case for now.

## Cross-Database Constraints

- No foreign keys between PostgreSQL (untenanted) and SQLite (tenanted)
- `WorkspaceMembership.user_id` is a cached reference, not a true FK
- Operations that touch both databases cannot be wrapped in a single transaction
- Sync operations are best-effort with error logging (see `sync_email_to_workspaces` rescue blocks)
