# Multi-Tenant Architecture (SaaS Mode)

Sabha's multi-tenant layer is a Rails engine in `saas/`, enabled via `Sabha.saas?` (set by `SAAS=true` env var or `tmp/saas.txt` marker file).

For self-hosted architecture, see [../ARCHITECTURE.md](../ARCHITECTURE.md).

> **License note:** The multi-tenant SaaS engine (`saas/` directory) is licensed under the [Sabha SaaS License](../../saas/LICENSE), not MIT. The core application (everything outside `saas/`) remains MIT-licensed.

---

## Overview

Multi-tenant mode enables:

- **Multiple workspaces** — each workspace has its own isolated SQLite database
- **Shared authentication** — users authenticate once, access multiple workspaces
- **Path-based routing** — URLs include workspace ID (e.g., `/1000001/rooms/general`)
- **Cross-workspace sessions** — single sign-on across all workspaces

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  PostgreSQL                          │
│           (untenanted database)                      │
│                                                      │
│  GlobalIdentity ─── WorkspaceMembership ─── Workspace│
│  GlobalSession                                       │
│  AuthCode                                            │
└─────────────────────────────────────────────────────┘
         │                    │                    │
         │              ┌─────┘                    │
         ▼              ▼                          ▼
┌──────────────┐ ┌──────────────┐        ┌──────────────┐
│  SQLite DB   │ │  SQLite DB   │  ...   │  SQLite DB   │
│ Workspace A  │ │ Workspace B  │        │ Workspace N  │
│              │ │              │        │              │
│ User, Room,  │ │ User, Room,  │        │ User, Room,  │
│ Message,     │ │ Message,     │        │ Message,     │
│ Membership...│ │ Membership...│        │ Membership...│
└──────────────┘ └──────────────┘        └──────────────┘
```

- **Untenanted database** (PostgreSQL): `GlobalIdentity`, `Workspace`, `WorkspaceMembership`, `GlobalSession`, `AuthCode` — these models inherit from `UntenantedRecord`
- **Tenanted databases** (SQLite, one per workspace): All application models (`User`, `Room`, `Message`, etc.) — stored at `storage/workspaces/{env}/{tenant_id}/db/main.sqlite3`
- Tenant isolation via `activerecord-tenanted` gem

---

## Request Flow

```
GET /1000001/rooms/42
         │
         ▼
PathRewriter middleware
  SCRIPT_NAME = /1000001
  PATH_INFO   = /rooms/42
         │
         ▼
TenantResolver
  extracts tenant ID from SCRIPT_NAME
  sets ApplicationRecord.current_tenant
         │
         ▼
Rails router (standard routing, unaware of tenant)
  matches /rooms/42 → RoomsController#show
         │
         ▼
URL helpers auto-include SCRIPT_NAME
  room_path(@room) → /1000001/rooms/42
```

The `PathRewriter` middleware moves the workspace prefix (e.g., `/1000001/`) from PATH_INFO to SCRIPT_NAME, enabling transparent URL generation. Controllers and views are unaware of the tenant prefix.

---

## Authentication

```
     ┌──────────────┐         ┌──────────────────┐
     │ GlobalIdentity│────────▶│ WorkspaceMembership│
     │ (email, cross-│         │ (links identity   │
     │  workspace)   │         │  to workspace)     │
     └──────┬───────┘         └────────┬───────────┘
            │                          │
            ▼                          ▼
     GlobalSession              User (per-workspace)
     (global_session_token      created/synced on
      cookie)                   workspace access)
            │
            ▼
     AuthCode (OTP only,
     no passwords in SaaS)
```

- `GlobalIdentity` is the cross-workspace user record (email + name, no password). The `name` field syncs bidirectionally with workspace `User` records — set during registration and updated when a user changes their name in any workspace.
- `GlobalSession` persists across workspaces via `global_session_token` cookie
- `WorkspaceMembership` links a `GlobalIdentity` to a specific workspace tenant
- SaaS mode enforces OTP-only authentication (no password auth)

### Current Context

```ruby
Current.global_session        # Cross-workspace session
Current.global_identity       # Identity (via global_session)
Current.workspace_membership  # Link to current workspace
Current.workspace             # Current Workspace record
# Current.user derived from workspace_membership.user
```

---

## Database

- **PostgreSQL** (`sabha_untenanted_{env}`): Platform-level records (identity, workspace, sessions)
- **SQLite** (per workspace): All application data, isolated per tenant
- Untenanted migrations: `saas/db/untenanted_migrate/`
- Tenanted migrations: standard `db/migrate/` (applied per-workspace)

See [postgres-untenanted.md](postgres-untenanted.md) for the full rationale.

---

## Deployment

```
┌──────────────────────────────────────────────────┐
│  Server                                           │
│                                                   │
│  kamal-proxy (:443, :80)  ─── TLS + routing       │
│      │ /cable     │ /*                             │
│      ▼            ▼                                │
│  AnyCable-Go   Web Container (SAAS=true)           │
│  (:8080)         Puma :3000 (SKIP_THRUSTER=true)   │
│                  Redis (in-container)               │
│                  Solid Queue workers                │
│                                                    │
│  Volume: /disk/sabha/ → /rails/storage             │
│  (per-workspace SQLite + PostgreSQL untenanted)     │
└──────────────────────────────────────────────────┘
```

- **kamal-proxy** handles TLS (Let's Encrypt) and routes `/cable` to AnyCable-Go, everything else to Puma
- **AnyCable-Go** runs as a Kamal accessory (`anycable/anycable-go:1.6`) on the same Docker network (`kamal`)
- `SKIP_THRUSTER=true` — Puma runs directly, no Thruster wrapper
- Deployed via `kamal deploy -d multitenant` (config: `config/deploy.multitenant.yml`)

See [DEPLOYMENT.md](DEPLOYMENT.md) for the full deployment guide.

---

## SaaS Engine Structure

```
saas/
├── lib/sabha/saas/engine.rb              # Engine config, routes
├── lib/sabha/saas/path_rewriter.rb       # Middleware: move workspace prefix into SCRIPT_NAME
├── app/models/
│   ├── global_identity.rb                # Cross-workspace user identity
│   ├── global_session.rb                 # Cross-workspace session
│   ├── workspace.rb                      # Workspace record
│   ├── workspace_membership.rb           # Identity ↔ workspace link
│   ├── auth_code.rb                      # OTP codes (SaaS equivalent of AuthToken)
│   └── untenanted_record.rb              # Base class for PostgreSQL models
├── app/controllers/saas/
│   ├── base_controller.rb                # Base for all SaaS controllers
│   ├── sessions_controller.rb            # Global sign-in
│   ├── registrations_controller.rb       # Global sign-up
│   ├── workspaces_controller.rb          # Workspace selection, creation, joining
│   ├── workspace_settings_controller.rb  # Workspace settings
│   ├── workspace_memberships_controller.rb # Leave workspace
│   ├── landing_controller.rb             # Landing page
│   └── auth_codes_controller.rb          # OTP verification
├── config/initializers/tenanting/
│   ├── tenant_resolver.rb                # Load/insert PathRewriter + tenant resolver
│   ├── application_record.rb             # Connect tenanted models to primary DB
│   ├── default_tenant.rb                 # Optional default tenant for local/dev use
│   ├── turbo.rb                          # Turbo broadcasts include workspace prefix
│   ├── active_storage.rb                 # Storage URLs include script_name
│   └── logging.rb                        # Tenant tags in logs
├── db/untenanted_migrate/                # PostgreSQL migrations
└── test/                                 # SaaS-specific test suite
```

---

## Background Jobs

Web push notification delivery captures tenant context before dispatching to the thread pool, ensuring notifications are sent from the correct workspace.

Solid Queue and ActionCable auto-propagate tenant context via the `activerecord-tenanted` gem — no manual tenant management in jobs or channels.

---

## URL Routing

SaaS mode prepends `/{workspace_id}/` to all workspace-scoped routes (handled transparently by the PathRewriter middleware).

```
https://sabha.co/                     # Landing page
https://sabha.co/session/new          # Global sign-in
https://sabha.co/workspaces           # Workspace selector
https://sabha.co/1000001/             # Workspace 1 home
https://sabha.co/1000001/rooms/general # Room in workspace 1
```

---

## Key Dependencies

| Gem | Purpose |
|-----|---------|
| `activerecord-tenanted` | Multi-tenant database isolation |
| `pg` | PostgreSQL adapter for untenanted database |

---

## Architectural Decisions

1. **Lazy user creation.** A `User` record in a workspace database is only created when a `GlobalIdentity` member first visits that workspace, avoiding pre-provisioning across all workspaces.

2. **Tenant context propagated automatically.** The `activerecord-tenanted` gem serializes `current_tenant` with Solid Queue job payloads and wraps ActionCable channel commands with the correct tenant, eliminating manual tenant management.

3. **PostgreSQL for the shared layer, SQLite for tenants.** Platform data (identities, sessions, workspaces) lives in managed PostgreSQL for reliability. Tenant data lives in SQLite for portability — users can download their database and self-host.

---

## See Also

- [DEPLOYMENT.md](DEPLOYMENT.md) — deploying in SaaS mode
- [activerecord-tenanted-guide.md](activerecord-tenanted-guide.md) — the tenanting gem
- [postgres-untenanted.md](postgres-untenanted.md) — why PostgreSQL for shared data
- [../ARCHITECTURE.md](../ARCHITECTURE.md) — self-hosted architecture
