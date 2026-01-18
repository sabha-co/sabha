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

| | **bin/dev** | **bin/dev + AnyCable** |
|---|---|---|
| **WebSockets** | ActionCable (Puma) | AnyCable-Go |
| **Cable Adapter** | `redis` | `any_cable` |
| **Jobs** | Inline (sync) | Inline (sync) |
| **Cache** | `:memory_store` | `:memory_store` |
| **Processes** | vite, web | vite, web, anycable |

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

| | **Development** | **Dev + AnyCable** | **bin/boot** | **Kamal** | **Campfire Cloud** |
|---|---|---|---|---|---|
| **Start** | `bin/dev` | `ANYCABLE_ENABLED=true bin/dev` | `bin/boot` | `kamal deploy` | `bin/boot` (Docker) |
| | | | | | |
| **WebSockets** | ActionCable | AnyCable-Go | ActionCable | AnyCable-Go | AnyCable-Go |
| **Cable Adapter** | `redis` | `any_cable` | `redis` | `any_cable` | `any_cable` |
| | | | | | |
| **Jobs** | Inline | Inline | Separate workers | Puma threads | Separate workers |
| **Job Mode** | sync | sync | `solid_queue:start` | `SOLID_QUEUE_IN_PUMA` | `solid_queue:start` |
| | | | | | |
| **Cache** | `:memory_store` | `:memory_store` | `:redis_cache_store` | `:redis_cache_store` | `:redis_cache_store` |
| | | | | | |
| **Database** | SQLite | SQLite | SQLite | SQLite | SQLite |
| | | | | | |
| **Redis** | External | External | Procfile starts it | External | Procfile starts it |
| **Redis For** | Cable | - | Cable + Cache | Cache | Cache |
| | | | | | |
| **Processes** | vite, web | vite, web, anycable | web, redis, workers | web + anycable | web, redis, workers, anycable, caddy |
| **TLS/Proxy** | None | None | Thruster | Thruster + Traefik | Caddy |

---


## Questions?

- Open an issue: [GitHub Issues](https://github.com/superforumio/campfire-ce/issues)
- See [CLAUDE.md](../CLAUDE.md) for AI-assisted development context
