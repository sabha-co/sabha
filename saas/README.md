# Sabha SaaS Layer

This is a Rails engine that extends [Sabha](https://github.com/sabha-co/sabha) with multi-tenancy for running a hosted version. Each workspace gets its own SQLite database, while shared platform data (identities, sessions, workspaces) lives in a PostgreSQL database.

Powered by the [`activerecord-tenanted`](https://github.com/basecamp/activerecord-tenanted) gem.

## Architecture

### Dual Database Setup

- **Untenanted (PostgreSQL):** Platform-wide data shared across all workspaces. Models inherit from `UntenantedRecord`.
- **Tenanted (SQLite per workspace):** All app models (`User`, `Room`, `Message`, etc.) inherit from `ApplicationRecord`. Each workspace gets its own database at `storage/workspaces/{env}/{tenant_id}/db/main.sqlite3`.


## Development

### Enabling SaaS Mode

```bash
bin/rails saas:enable       # Writes tmp/saas.txt marker; bin/* binstubs pick Gemfile.saas on next run
bundle install
bin/rails saas:setup        # Creates default workspace (ID 1000001)
bin/dev
```

To go back to open-source mode:

```bash
bin/rails saas:disable      # Removes tmp/saas.txt
bundle install
bin/dev
```

Check the current mode any time:

```bash
bin/rails saas:status
```

You can also enable SaaS mode temporarily for a single session:

```bash
SAAS=true bin/dev
```

### Workspace Management

```bash
bin/rails workspace:list                    # List all workspaces
bin/rails workspace:create[name,email]      # Create new workspace
bin/rails workspace:destroy[1000001]        # Destroy workspace
bin/rails workspace:info[1000001]           # Show workspace details
bin/rails saas:reset                        # Reset everything (destructive)
```

### Database Migrations

Standard migrations in `db/migrate/` apply to tenanted (per-workspace) databases. Untenanted migrations go in `saas/db/untenanted_migrate/`.

In SaaS mode, run:

```bash
SAAS=true bin/rails db:migrate:primary      # Tenanted; auto-chains db:migrate:untenanted
```

To run the untenanted migrations on their own:

```bash
SAAS=true bin/rails db:migrate:untenanted
```

### Updating the Engine

When you change `Gemfile`, keep `Gemfile.saas.lock` in sync:

```bash
BUNDLE_GEMFILE=Gemfile.saas bundle install
```

After bumping the engine version in `sabha-saas.gemspec`, refresh just its lockfile entry:

```bash
BUNDLE_GEMFILE=Gemfile.saas bundle update --conservative sabha-saas
```

### Running Tests

```bash
# Full SaaS test suite
SAAS=true bin/rails test saas/test/

# Single test file
SAAS=true bin/rails test saas/test/models/workspace_test.rb
```

## License

The code in this directory is proprietary. See [LICENSE](LICENSE) for details. The core Sabha application is available under the [MIT License](../LICENSE.md).
