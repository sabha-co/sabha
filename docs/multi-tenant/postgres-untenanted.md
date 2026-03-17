# PostgreSQL for the Untenanted Database

## Decision

The shared untenanted database (global identities, workspaces, sessions) runs on PostgreSQL. Per-workspace tenant databases remain on SQLite.

## Architecture

|  | **Self-hosted** | **SaaS** |
|---|---|---|
| **Shared/Global DB** | SQLite | PostgreSQL |
| **Per-tenant DB** | N/A (single tenant) | SQLite per workspace |
| **Queue DB** | SQLite | SQLite |
| **Cable DB** | Redis | Redis |
| **Tenant isolation** | N/A | Separate SQLite files |
| **Infra dependency** | None | Managed Postgres |
| **DB adapter gem** | `sqlite3` | `sqlite3` + `pg` |
| **Tenant portability** | N/A | Yes (download SQLite file) |

## Why PostgreSQL for the shared layer

The untenanted database is the platform layer -- identities, sessions, workspaces. It runs as a separate managed service that can be independently backed up, replicated, and recovered. PostgreSQL is the right tool for data that must be reliable at the global level.

## Why SQLite stays for tenants

Each workspace gets its own SQLite file. This is the key to Sabha's portability story: if a user wants to leave the multi-tenant platform and self-host, they download their SQLite database and run their own Sabha instance. No migration, no export — just take your file and go.

This gives us the best of both worlds:
- **Platform data (Postgres):** managed, replicated, reliable — the stuff we operate
- **Tenant data (SQLite):** portable, isolated, self-contained — the stuff users own

## Tables in the untenanted database

| Table | Purpose |
|-------|---------|
| `global_identities` | Cross-workspace user identity (email) |
| `global_sessions` | Cross-workspace session management |
| `auth_codes` | OTP codes for global identity auth |
| `workspaces` | Workspace registry |
| `workspace_memberships` | Links identities to workspaces |
| `workspace_external_id_sequences` | External ID generation |

## Configuration

### database.yml

The untenanted database config is only active in SaaS mode (`Sabha.saas?`). It uses a standalone PostgreSQL config block — it does NOT inherit from the `&default` anchor (which has SQLite-specific options like `timeout`, `retries`, `default_transaction_mode`).

```yaml
untenanted:
  adapter: postgresql
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 10 } %>
  url: <%= ENV.fetch("UNTENANTED_DATABASE_URL", "postgres://localhost/sabha_untenanted_development") %>
  migrations_paths: saas/db/untenanted_migrate
```

Connection details (host, port, database, credentials, SSL) are all in the URL.

### Environment variable

| Variable | Default | Description |
|----------|---------|-------------|
| `UNTENANTED_DATABASE_URL` | `postgres://localhost/sabha_untenanted_<env>` | PostgreSQL connection URL |

Production URL includes SSL params: `postgres://user:pass@host:port/db?sslmode=require`

### Development setup

PostgreSQL must be running locally. With Homebrew:

```bash
brew install postgresql
brew services start postgresql
```

Then create the databases:

```bash
SAAS=true bin/rails db:create db:migrate
```

### Production deployment (Kamal)

Production uses a managed PostgreSQL service. No database accessory in Kamal -- the database is external infrastructure.

Set `UNTENANTED_DATABASE_URL` in `.kamal/secrets` with the full connection string from your provider. SSL params are included in the URL (e.g., `?sslmode=require`).

## Migrations

All 9 untenanted migrations use pure ActiveRecord DSL — no SQLite-specific syntax. They run against PostgreSQL without modification.

## Models

All 6 untenanted models inherit from `UntenantedRecord`, which uses `connects_to`. The adapter is determined entirely by `database.yml` — no model changes needed.
