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

The authoritative list is `saas/db/untenanted_schema.rb`.

| Table | Purpose |
|-------|---------|
| `global_identities` | Cross-workspace user identity (email, name) |
| `global_sessions` | Cross-workspace session management |
| `auth_codes` | OTP codes for global identity auth |
| `workspaces` | Workspace registry |
| `workspace_memberships` | Links identities to workspaces |
| `workspace_external_id_sequences` | Allocator for the URL-visible workspace IDs |
| `workspace_backups` | R2-backed SQLite snapshots (see [DEPLOYMENT.md](DEPLOYMENT.md#backups)) |
| `workspace_snapshots` | Point-in-time snapshot metadata |

## Configuration

### database.yml

The full SaaS database config is in `saas/config/database.yml` and is selected by `config/database.yml` when `Sabha.saas?` is true. It uses two YAML anchors: `&sqlite` for the per-tenant primary and queue databases, and `&untenanted` for the shared PostgreSQL block. The PostgreSQL block does NOT inherit `&sqlite` because SQLite-specific options (`timeout`, `retries`, `default_transaction_mode`) are not valid for `pg`.

Per-environment shape:

```yaml
primary:
  <<: *sqlite
  database: "storage/workspaces/<env>/%{tenant}/db/main.sqlite3"
  tenanted: true
  max_connection_pools: 50          # 100 in production
untenanted:
  <<: *untenanted
  url: <%= ENV.fetch("UNTENANTED_DATABASE_URL", "postgres://localhost/sabha_untenanted_<env>") %>
queue:
  <<: *sqlite
  database: storage/db/<env>_queue.sqlite3
  migrations_paths: db/queue_migrate
```

The `&untenanted` anchor sets `migrations_paths: saas/db/untenanted_migrate` and `schema_dump: saas/db/untenanted_schema.rb`. Connection details (host, port, database, credentials, SSL) are all in the URL.

### Environment variable

| Variable | Default | Description |
|----------|---------|-------------|
| `UNTENANTED_DATABASE_URL` | `postgres://localhost/sabha_untenanted_<env>` | PostgreSQL connection URL |

Production URL includes SSL params: `postgres://user:pass@host:port/db?sslmode=require`

### Development setup

**PostgreSQL 18 is the standard** across CI, local development, and production —
keep them on one major so nothing test-splits. A local server on 17 or older
will run the suite but drifts from what CI (the untenanted service is
`postgres:18`) and production run; upgrade to match. With Homebrew:

```bash
brew install postgresql@18
brew services start postgresql@18
```

Then create the databases:

```bash
SAAS=true bin/rails db:create db:migrate
```

### Production deployment (Kamal)

Production uses a managed PostgreSQL service. No database accessory in Kamal — the database is external infrastructure.

`UNTENANTED_DATABASE_URL` lives in `.env.multitenant` (gitignored) and is forwarded into the container via `.kamal/secrets.multitenant`. SSL params are included in the URL (e.g., `?sslmode=require`).

## Migrations

Untenanted migrations live in `saas/db/untenanted_migrate/` and use pure ActiveRecord DSL — no SQLite-specific syntax — so they apply against PostgreSQL without modification.

## Models

Every model that targets the untenanted database inherits from `UntenantedRecord`, which `connects_to database: { writing: :untenanted, reading: :untenanted }`. The adapter is determined entirely by `database.yml` — no model changes needed. Current subclasses: `GlobalIdentity`, `GlobalSession`, `AuthCode`, `Workspace`, `WorkspaceMembership`, `Workspace::ExternalIdSequence`, `Workspace::Backup`, `Workspace::Snapshot`.
