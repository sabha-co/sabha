# Sabha SaaS Layer

This is a Rails engine that extends [Sabha](https://github.com/sabha-co/sabha) with multi-tenancy for running a hosted version. Each workspace gets its own SQLite database, while shared platform data (identities, sessions, workspaces) lives in a PostgreSQL database.

Powered by the [`activerecord-tenanted`](https://github.com/basecamp/activerecord-tenanted) gem.

## Architecture

### Dual Database Setup

- **Untenanted (PostgreSQL):** Platform-wide data shared across all workspaces. Models inherit from `UntenantedRecord`.
- **Tenanted (SQLite per workspace):** All app models (`User`, `Room`, `Message`, etc.) inherit from `ApplicationRecord`. Each workspace gets its own database at `storage/{env}/workspaces/{tenant_id}/main.sqlite3`.

### Key Models

| Model | Database | Purpose |
|-------|----------|---------|
| `GlobalIdentity` | Untenanted | Cross-workspace user identity (email + OTP) |
| `GlobalSession` | Untenanted | Session token stored in `global_session_token` cookie |
| `WorkspaceMembership` | Untenanted | Links a GlobalIdentity to a workspace |
| `Workspace` | Untenanted | Workspace registry (name, ID, settings) |
| `AuthCode` | Untenanted | OTP codes for GlobalIdentity (parallels AuthToken in self-hosted) |
| `User` | Tenanted | Per-workspace user (name, role, avatar) |
| `Account` | Tenanted | Per-workspace settings (singleton) |

### Authentication Flow

1. User signs in with email → `AuthCode` OTP sent
2. OTP verified → `GlobalSession` created, `global_session_token` cookie set
3. User selects a workspace → `WorkspaceMembership` looked up
4. `Current.user` derives from `workspace_membership.user` within the tenant

### URL Structure

```
/                           # Landing page (sign in/up or workspace selector)
/login                      # Sign in
/signup                     # Sign up
/workspaces                 # Workspace list
/workspaces/new             # Create workspace
/1000001/                   # Workspace root
/1000001/rooms/general      # Room within a workspace
```

The `PathRewriter` middleware extracts the workspace ID prefix and moves it to `SCRIPT_NAME`, so Rails URL helpers automatically include it.

### Directory Structure

```
saas/
├── app/
│   ├── controllers/saas/       # SaaS controllers (inherit from Saas::BaseController)
│   ├── models/                 # Untenanted models
│   ├── views/saas/             # SaaS-specific views
│   ├── mailers/                # Auth code mailer
│   └── helpers/                # Workspace selector helper
├── config/
│   ├── routes.rb               # SaaS routes (prepended to main routes)
│   └── initializers/tenanting/ # Tenant resolution, path rewriting, Turbo/Storage hooks
├── db/
│   └── untenanted_migrate/     # PostgreSQL migrations for untenanted tables
├── test/
│   ├── models/                 # Model tests
│   ├── controllers/saas/       # Controller tests
│   └── fixtures/               # Untenanted model fixtures
└── lib/sabha/saas/
    └── engine.rb               # Engine configuration
```

### Tenant Initializers (`config/initializers/tenanting/`)

- `tenant_resolver.rb` — Extracts tenant ID from `SCRIPT_NAME`
- `path_rewriter.rb` — Middleware moves workspace prefix to `SCRIPT_NAME`
- `turbo.rb` — Ensures Turbo Stream broadcasts include the workspace prefix
- `active_storage.rb` — Sets URL options with `script_name` for attachments
- `logging.rb` — Adds tenant tags to Rails and SQL logs

## Development

### Enabling SaaS Mode

```bash
bin/rails saas:enable       # Creates tmp/saas.txt, switches to Gemfile.saas
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

After running `bin/rails db:migrate`, always also run:

```bash
SAAS=true bin/rails db:migrate:primary      # Apply to tenanted databases
SAAS=true bin/rails db:migrate:untenanted   # Only if migration touches untenanted tables
```

### Updating the Engine

After making changes to this engine, update the lockfile:

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
