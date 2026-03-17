# Development Guide

Guide for contributing to Sabha.

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
git clone https://github.com/sabha-co/sabha.git
cd sabha
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

A single Rails server process (Puma) with Solid Queue running in-process.

For active CSS development, run the Tailwind watcher in a separate terminal:

```bash
pnpm run build:css:watch
```

### With AnyCable (optional)

For production-like WebSocket handling:

```bash
bin/dev --anycable
```

This uses foreman to run Rails + AnyCable-Go + CSS watcher together.

Requires `anycable-go` installed:

```bash
brew install anycable-go
```

---

> For SaaS (multi-tenant) development, see [multi-tenant/DEVELOPMENT.md](./multi-tenant/DEVELOPMENT.md).

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
| CSS | Tailwind v4 (via `@tailwindcss/cli`) |
| JS loading | Importmap |

### Directory Structure

```
app/
├── channels/        # ActionCable channels
├── controllers/     # Rails controllers
├── javascript/      # Stimulus controllers, channels, helpers
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
| **Jobs** | Solid Queue (in Puma) | Solid Queue (in Puma) |
| **Cache** | `:memory_store` | `:memory_store` |
| **Processes** | web | web, css, anycable |

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

Controllers go in `app/javascript/controllers/` and are loaded via importmap.

### Add a background job

```bash
bin/rails generate job JobName
```

Jobs use Solid Queue. In development, jobs run in Puma via the `solid_queue` plugin.

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

## Questions?

- Open an issue: [GitHub Issues](https://github.com/sabha-co/sabha/issues)
- See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed system architecture
