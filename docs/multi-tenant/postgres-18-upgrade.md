# Upgrading the Untenanted PostgreSQL from 17 to 18

A runbook for moving the shared untenanted database (global identities, sessions,
workspaces) from PostgreSQL major 17 to 18. It carries data and availability
risk, not code risk: the application is already exercised against Postgres 18 in
CI (the untenanted service runs `postgres:18`), so this is purely an
infrastructure cutover.

Only the untenanted database is affected. Per-workspace tenant databases are
SQLite and are untouched.

## Before you start

- **Confirm the cutover mechanism for your managed provider.** `UNTENANTED_DATABASE_URL`
  points at a managed Postgres instance, and how a major upgrade happens depends
  on the provider. There are two shapes:
  - **In-place major upgrade** — the provider upgrades the running instance to 18
    and keeps the same (or a provider-issued new) endpoint. Fastest, least moving
    parts. Confirm the provider does not silently drop the old instance.
  - **Dump + restore into a fresh 18 instance** — provision a new Postgres 18
    instance, load a dump of the 17 data into it, and repoint
    `UNTENANTED_DATABASE_URL`. Use this when the provider has no in-place path, or
    when you want the 17 instance kept intact as an instant rollback.

  Pick one before scheduling. The rest of this runbook applies to both; the
  cutover step branches.

- **Schedule a maintenance window.** Untenanted records gate every request (login
  and workspace resolution), so the cutover briefly affects all workspaces.

- **Confirm 18 is validated.** CI's untenanted leg must be green on `postgres:18`,
  and ideally the change has run on a staging untenanted database first.

## 1. Snapshot the pre-upgrade state

Capture row counts to compare after the cutover. Run against the current
(17) untenanted database:

```sql
SELECT version();
SELECT
  (SELECT count(*) FROM global_identities)     AS global_identities,
  (SELECT count(*) FROM workspaces)            AS workspaces,
  (SELECT count(*) FROM workspace_memberships) AS workspace_memberships,
  (SELECT count(*) FROM global_sessions)       AS global_sessions;
```

Record the output. These are the numbers the post-upgrade smoke check must match.

## 2. Take and verify a backup

Take a logical backup before touching anything. Keep credentials out of the
process argument list (use `~/.pgpass` or a `PGPASSWORD` environment variable,
not `--password` on the command line), and lock the dump down:

```bash
umask 077   # dump is created 0600
pg_dump "$UNTENANTED_DATABASE_URL" --format=custom --file=untenanted-17.dump
```

Verify the dump is non-empty and structurally readable before trusting it:

```bash
test -s untenanted-17.dump || { echo "backup is empty"; exit 1; }
pg_restore --list untenanted-17.dump > /dev/null && echo "backup verified"
```

`pg_dump`/`pg_restore` must not be older than the server — use the client from
the PostgreSQL 18 packages (the runtime image already ships
`postgresql-client-18`).

## 3. Cut over

**In-place path:** trigger the provider's major-version upgrade to 18 within the
window. If the provider issues a new endpoint, note it for step 4.

**Dump + restore path:**

```bash
# Restore into the fresh Postgres 18 instance
pg_restore --dbname "$NEW_UNTENANTED_18_URL" --no-owner --no-privileges untenanted-17.dump
```

Then repoint the app at the new instance. Keep the external SSL requirement in
the URL (`?sslmode=require`):

1. Update `UNTENANTED_DATABASE_URL` in `.env.multitenant` (and
   `.kamal/secrets.multitenant`) to the Postgres 18 endpoint.
2. Redeploy the multitenant service so the new URL takes effect.

Do **not** decommission the 17 instance yet — it is the rollback.

## 4. Verify

Run against the upgraded (18) untenanted database and compare to step 1:

```sql
SELECT version();   -- must report 18
SELECT
  (SELECT count(*) FROM global_identities)     AS global_identities,
  (SELECT count(*) FROM workspaces)            AS workspaces,
  (SELECT count(*) FROM workspace_memberships) AS workspace_memberships,
  (SELECT count(*) FROM global_sessions)       AS global_sessions;
```

- `version()` reports 18.
- All four row counts match the pre-upgrade snapshot.
- A real login → workspace-membership resolution → session path works in
  production (sign in, land in a workspace, confirm the session sticks).

## 5. Finish or roll back

- **Healthy:** once verification passes and the app has run cleanly for a while,
  decommission the 17 instance and retire the `untenanted-17.dump` per your
  retention policy.
- **Broken:** roll back before removing the fallback.
  - *In-place:* restore `untenanted-17.dump` into a 17 instance (or the
    provider's point-in-time recovery) and repoint `UNTENANTED_DATABASE_URL`.
  - *Dump + restore:* repoint `UNTENANTED_DATABASE_URL` back at the retained 17
    instance and redeploy.

A major-version upgrade rewrites the cluster and is not reversible in place, so
the retained 17 instance and the verified backup are the only rollback. Keep
both until 18 is confirmed healthy.
