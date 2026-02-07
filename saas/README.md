# Sabha SaaS Layer

This folder contains the multi-tenancy SaaS layer for Sabha. It's implemented as a Rails engine that extends the core application with:

- **GlobalIdentity**: Cross-workspace user authentication (email + OTP)
- **Workspace isolation**: Each workspace has its own SQLite database
- **Workspace selector**: UI for switching between workspaces
- **Path-based routing**: `/1000001/rooms/general` pattern

## Enabling SaaS Mode

```bash
# Option 1: Environment variable (temporary)
SAAS=true bin/setup

# Option 2: Persistent marker file
bin/rails saas:enable
bin/setup
```

Both options auto-select `Gemfile.saas` which extends the base Gemfile with multi-tenancy deps.

## Directory Structure

```
saas/
├── app/
│   ├── controllers/
│   │   └── saas/              # SaaS-specific controllers
│   ├── models/                # Untenanted models (GlobalIdentity, etc.)
│   ├── views/saas/            # SaaS-specific views
│   ├── mailers/               # Magic link mailer
│   └── helpers/               # Workspace selector helper
├── config/
│   ├── routes.rb              # SaaS routes (prepended to main routes)
│   └── initializers/
│       └── tenanting/         # Tenant configuration
├── db/
│   └── untenanted_migrate/    # Migrations for untenanted database
└── lib/
    └── sabha/saas/
        └── engine.rb          # Rails engine configuration
```

## Key Models

| Model | Database | Purpose |
|-------|----------|---------|
| `GlobalIdentity` | Untenanted | Cross-workspace auth (email + OTP) |
| `GlobalSession` | Untenanted | Session token for cookie |
| `WorkspaceMembership` | Untenanted | Links identity → workspace |
| `Workspace` | Untenanted | Workspace registry |
| `User` | Tenanted | Workspace presence (name, role) |
| `Account` | Tenanted | Workspace settings |

## URL Structure

```
/                           # Landing page:
                            #   - Unauthenticated: sign in/sign up form
                            #   - Authenticated: blank page + workspace selector sidebar
/login                      # Sign in (alternative entry point)
/signup                     # Sign up (alternative entry point)
/workspaces                 # Workspace list (legacy, /workspaces/new for create)
/1000001/                   # Workspace root
/1000001/rooms/general      # Room in workspace
```

**Note:** Authenticated users always see the workspace selector sidebar on `/` and choose which workspace to enter. No auto-redirect to any workspace.

## Development

```bash
# Check SaaS mode status
bin/rails saas:status

# Create a new workspace
bin/rails workspace:create[name]

# List workspaces
bin/rails workspace:list

# Run console with specific workspace
ARTENANT=1000001 bin/rails console
```
