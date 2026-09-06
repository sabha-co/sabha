# Development Guide

Guide for contributing to Sabha.

---

## Prerequisites

- **Ruby** 4.0+ (check `.ruby-version`)
- **Node.js** 24+ and **pnpm** (optional: only the Herb ERB linter needs them)
- **anycable-go** — the WebSocket server; required for all real-time delivery. See the [AnyCable install guide](https://docs.anycable.io/anycable-go/getting_started).
- **Redis** (for Kredis)
- **libvips** (for image processing)
- **SQLite** 3.35+

### macOS

```bash
brew install ruby node pnpm redis libvips sqlite anycable-go
brew services start redis
```

### Ubuntu/Debian

```bash
sudo apt-get install -y libvips-dev redis-server sqlite3 libsqlite3-dev
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo bash -
sudo apt-get install -y nodejs
npm install -g pnpm

# anycable-go isn't packaged for apt — install a release binary or via npm.
# See https://docs.anycable.io/anycable-go/getting_started
npm install -g @anycable/anycable-go
```

---

## Setup

```bash
git clone https://github.com/sabha-co/sabha.git
cd sabha
bin/setup
```

This installs gems, the Herb linter (when pnpm is present), `anycable-go` (on macOS), and prepares the database. There is no CSS build: stylesheets are served as written.

To populate development data (users, rooms, messages):

```bash
bin/rails db:seed
```

---

## Running Locally

```bash
bin/dev
```

Opens at `http://localhost:3000`

### What `bin/dev` starts

Foreman runs two processes together: the Rails server (Puma, with Solid Queue
in-process) and `anycable-go`. AnyCable is required —
it carries all real-time delivery (live messages, typing, presence) — so
`bin/dev` always boots it.

`anycable-go` must be on your PATH. `bin/setup` installs it on macOS; otherwise:

```bash
brew install anycable-go   # macOS
# other platforms: https://docs.anycable.io/anycable-go/getting_started
```

`bin/dev` preflights for the binary and exits with an install hint if it's missing.

---

> For SaaS (multi-tenant) development, see [multi-tenant/DEVELOPMENT.md](./multi-tenant/DEVELOPMENT.md).

---

## Running Tests

```bash
bin/rails test                    # All tests
bin/rails test test/models        # Model tests only
bin/rails test test/models/user_test.rb  # Single file
```

### Test stack

- **Minitest** - Test framework
- **Mocha** - Mocking/stubbing
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

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full system architecture, domain model, and deployment details.

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
