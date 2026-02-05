# Development Guide

Guide for contributing to Campfire-CE.

---

## Prerequisites

- **Ruby** 4.0+ (check `.ruby-version`)
- **Node.js** 24+ and **pnpm**
- **Redis** (for ActionCable in development)
- **libvips** (for image processing)
- **SQLite** 3.35+

### macOS

```bash
brew install ruby node pnpm redis libvips sqlite
brew services start redis
```

### Ubuntu/Debian

```bash
sudo apt-get install -y libvips-dev redis-server sqlite3 libsqlite3-dev
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo bash -
sudo apt-get install -y nodejs
npm install -g pnpm
```

---

## Setup

```bash
git clone https://github.com/superforumio/campfire-ce.git
cd campfire-ce
bin/setup
```

This installs gems, pnpm packages, prepares the database, and builds Tailwind.

---

## Running Locally

```bash
bin/dev
```

Opens at `http://localhost:3000`

### What `bin/dev` starts

| Process | Purpose |
|---------|---------|
| `web` | Rails server (Puma) |
| `vite` | Vite dev server for Tailwind CSS |

### With AnyCable (optional)

For production-like WebSocket handling:

```bash
ANYCABLE_ENABLED=true bin/dev
```

Requires `anycable-go` installed:

```bash
brew install anycable-go
```

---

## SaaS Mode (Multi-Tenant)

Campfire-CE supports two deployment modes:

| Mode | Description | Gemfile |
|------|-------------|---------|
| **Self-host** (default) | Single-tenant, one workspace | `Gemfile` |
| **SaaS mode** | Multi-tenant, database-per-workspace | `Gemfile.saas` |

### Switching Modes

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

### SaaS Architecture

When SaaS mode is enabled:

- **Multi-tenant database**: Each workspace gets its own SQLite database via `activerecord-tenanted` gem
- **Path-based routing**: URLs include workspace ID (`/1000001/rooms/general`)
- **GlobalIdentity**: Cross-workspace user authentication
- **Workspace model**: Registry of all workspaces (in untenanted database)
- **Workspace selector**: Sidebar for users with multiple workspaces

### SaaS-Specific Files

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
└── lib/campfire/saas/          # Engine definition

Gemfile.saas                    # Extends Gemfile with tenanting gems
```

See `docs/multi-tenant/` for detailed architecture documentation.

---

## Running Tests

```bash
bin/rails test                    # All tests
bin/rails test test/models        # Model tests only
bin/rails test test/models/user_test.rb  # Single file
bin/rails test:system             # Browser tests (requires Chrome)
```

### Test stack

- **Minitest** - Test framework
- **Mocha** - Mocking/stubbing
- **Capybara** - Browser testing
- **WebMock** - HTTP stubbing

### Test data strategy

- **Real database**: Tests use the standard Rails test DB.
- **Fixtures**: Loaded once per suite, then accessed via `fixtures :all` (self-hosted) or explicit fixture lists (SaaS).
- **Transactions**: Per-test transactions with rollback (default Rails `use_transactional_tests`).

---

## Code Style

```bash
bin/rubocop                       # Check Ruby style
bin/rubocop -a                    # Auto-fix
```

Uses `rubocop-rails-omakase` (Rails default style).

Lefthook runs rubocop automatically on commit.

---

## Architecture Overview

### Tech Stack

| Layer | Technology |
|-------|------------|
| Framework | Rails (edge) |
| Database | SQLite |
| Real-time | ActionCable / AnyCable |
| Jobs | Solid Queue (SQLite-backed) |
| Frontend | Hotwire (Turbo + Stimulus) |
| CSS | Tailwind v4 (via Vite) |
| JS loading | Importmap |

### Directory Structure

```
app/
├── channels/        # ActionCable channels
├── controllers/     # Rails controllers
├── frontend/        # Vite entrypoints (CSS only)
│   └── controllers/ # Stimulus controllers
├── jobs/            # Solid Queue jobs
├── models/          # ActiveRecord models
│   ├── concerns/    # Shared model behavior
│   └── rooms/       # Room STI subclasses
└── views/           # ERB templates

config/
├── cable.yml        # ActionCable/AnyCable config
├── database.yml     # SQLite databases
├── queue.yml        # Solid Queue config
└── deploy.yml       # Kamal deployment
```

### Key Patterns

**Room Types (STI)**
```
Room
├── Rooms::Open      # Public rooms
├── Rooms::Closed    # Private rooms
├── Rooms::Direct    # DMs
└── Rooms::Thread    # Threaded replies
```

**Current Context**
```ruby
Current.user         # Logged-in user
Current.session      # Browser session
```

**Soft Deletion**
```ruby
include Deactivatable  # Adds `active` scope
message.deactivate!    # Sets active: false
```

---

## Environment Modes

| | **bin/dev** | **bin/dev + AnyCable** | **SaaS mode** |
|---|---|---|---|
| **Tenant Mode** | Single-tenant | Single-tenant | Multi-tenant |
| **WebSockets** | ActionCable (Puma) | AnyCable-Go | ActionCable (Puma) |
| **Cable Adapter** | `redis` | `any_cable` | `redis` |
| **Jobs** | Inline (sync) | Inline (sync) | Inline (sync) |
| **Cache** | `:memory_store` | `:memory_store` | `:memory_store` |
| **Processes** | vite, web | vite, web, anycable | vite, web |
| **Gemfile** | `Gemfile` | `Gemfile` | `Gemfile.saas` |

See [DEPLOYMENT.md](./DEPLOYMENT.md) for production modes.

---

## Common Tasks

### Add a migration

```bash
bin/rails generate migration AddFieldToModel field:type
bin/rails db:migrate
```

### Add a Stimulus controller

```bash
bin/rails generate stimulus controller_name
```

Controllers go in `app/frontend/controllers/` and are loaded via importmap.

### Add a background job

```bash
bin/rails generate job JobName
```

Jobs use Solid Queue. In development, jobs run inline (synchronously).

### Reset database

```bash
bin/rails db:reset
```

---

## Debugging

### Rails console

```bash
bin/rails console
```

### Debug gem

Add `debugger` anywhere in code, then interact in terminal.

```ruby
def show
  debugger  # Execution stops here
  @room = Room.find(params[:id])
end
```

### Logs

```bash
tail -f log/development.log
```

### ActionCable debugging

```javascript
// In browser console
ActionCable.logger.enabled = true
```

---

## Pull Request Guidelines

1. **Branch from `main`**
2. **Write tests** for new features
3. **Run `bin/rubocop`** before committing
4. **Keep commits focused** - one logical change per commit
5. **Update docs** if adding user-facing features

### Commit message format

```
Short summary (50 chars or less)

Longer description if needed. Explain the "why" not the "what".
The code shows what changed; the message explains why.
```

---

## Architecture Comparison

| | **Development** | **Dev + AnyCable** | **SaaS Dev** | **bin/boot** | **Kamal** | **Campfire Cloud** |
|---|---|---|---|---|---|---|
| **Start** | `bin/dev` | `ANYCABLE_ENABLED=true bin/dev` | `bin/rails saas:enable && bundle && bin/dev` | `bin/boot` | `kamal deploy` | `bin/boot` (Docker) |
| **Tenant Mode** | Single | Single | Multi | Single | Single | Multi |
| | | | | | | |
| **WebSockets** | ActionCable | AnyCable-Go | ActionCable | ActionCable | AnyCable-Go | AnyCable-Go |
| **Cable Adapter** | `redis` | `any_cable` | `redis` | `redis` | `any_cable` | `any_cable` |
| | | | | | | |
| **Jobs** | Inline | Inline | Inline | Separate workers | Puma threads | Separate workers |
| **Job Mode** | sync | sync | sync | `solid_queue:start` | `SOLID_QUEUE_IN_PUMA` | `solid_queue:start` |
| | | | | | | |
| **Cache** | `:memory_store` | `:memory_store` | `:memory_store` | `:redis_cache_store` | `:redis_cache_store` | `:redis_cache_store` |
| | | | | | | |
| **Database** | SQLite | SQLite | SQLite per-tenant | SQLite | SQLite | SQLite per-tenant |
| | | | | | | |
| **Redis** | External | External | External | Procfile starts it | External | Procfile starts it |
| **Redis For** | Cable | - | Cable | Cable + Cache | Cache | Cache |
| | | | | | | |
| **Processes** | vite, web | vite, web, anycable | vite, web | web, redis, workers | web + anycable | web, redis, workers, anycable, caddy |
| **TLS/Proxy** | None | None | None | Thruster | Thruster + Traefik | Caddy |

---


## Questions?

- Open an issue: [GitHub Issues](https://github.com/superforumio/campfire-ce/issues)
- See [CLAUDE.md](../CLAUDE.md) for AI-assisted development context
