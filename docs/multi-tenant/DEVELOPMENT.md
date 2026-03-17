# Developing Multi-Tenant (SaaS Mode)

Guide for developing Sabha in multi-tenant SaaS mode.

For self-hosted development, see [../DEVELOPMENT.md](../DEVELOPMENT.md).

> **License note:** The multi-tenant SaaS engine (`saas/` directory) is licensed under the [Sabha SaaS License](../../saas/LICENSE), not MIT.

---

## Prerequisites

Everything from the [self-hosted prerequisites](../DEVELOPMENT.md#prerequisites), plus:

- **PostgreSQL** 16+ (for the untenanted database)

```bash
# macOS
brew install postgresql@16
brew services start postgresql@16

# Ubuntu/Debian
sudo apt-get install -y postgresql postgresql-contrib
```

---

## Switching Modes

Sabha supports two deployment modes:

| Mode | Description | Gemfile |
|------|-------------|---------|
| **Self-host** (default) | Single-tenant, one workspace | `Gemfile` |
| **SaaS mode** | Multi-tenant, database-per-workspace | `Gemfile.saas` |

```bash
# Check current mode
bin/rails saas:status

# Enable SaaS mode
bin/rails saas:enable
bundle install    # Important: switches to Gemfile.saas
bin/dev

# Disable SaaS mode
bin/rails saas:disable
bundle install    # Important: switches back to Gemfile
bin/dev
```

### How It Works

- `bin/rails saas:enable` creates `tmp/saas.txt` marker file
- `bin/rails saas:disable` removes `tmp/saas.txt`
- The marker file determines which Gemfile is used during `bundle install`
- For temporary SaaS mode (single session): `SAAS=true bin/dev`

---

## Gemfile Sync

When updating gems in `Gemfile`, also update the SaaS lockfile:

```bash
BUNDLE_GEMFILE=Gemfile.saas bundle install
```

---

## Database Migrations

```bash
# Migrate both tenanted and untenanted databases
SAAS=true bin/rails db:migrate:primary

# Untenanted migrations only
SAAS=true bin/rails db:migrate:untenanted
```

- Untenanted migrations live in `saas/db/untenanted_migrate/`
- Tenanted migrations use the standard `db/migrate/` path (applied per-workspace)

---

## Running Tests

```bash
# SaaS test suite
SAAS=true bin/rails test saas/test/

# Single SaaS test file
SAAS=true bin/rails test saas/test/models/workspace_test.rb
```

When making changes that affect both modes, run both test suites:

```bash
bin/rails test                          # Self-hosted
SAAS=true bin/rails test saas/test/     # SaaS
```

---

## Environment Modes

| | **SaaS mode (`SAAS=true bin/dev`)** |
|---|---|
| **Tenant Mode** | Multi-tenant |
| **WebSockets** | ActionCable (Puma) |
| **Cable Adapter** | `redis` |
| **Jobs** | Solid Queue (in Puma) |
| **Cache** | `:memory_store` |
| **Processes** | web |
| **Gemfile** | `Gemfile.saas` |

---

## SaaS-Specific Files

```
saas/                           # SaaS engine (Rails Engine)
├── app/
│   ├── controllers/            # Workspace management
│   ├── models/                 # GlobalIdentity, Workspace, etc.
│   └── views/                  # Workspace selector, landing pages
├── config/
│   ├── initializers/tenanting/ # Tenant context setup
│   └── routes.rb               # SaaS routes (prepended)
├── db/untenanted_migrate/      # Migrations for untenanted DB
└── lib/sabha/saas/             # Engine definition

Gemfile.saas                    # Extends Gemfile with tenanting gems
```

---

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) — multi-tenant architecture
- [DEPLOYMENT.md](DEPLOYMENT.md) — deploying in SaaS mode
- [activerecord-tenanted-guide.md](activerecord-tenanted-guide.md) — the tenanting gem
- [../DEVELOPMENT.md](../DEVELOPMENT.md) — self-hosted development
