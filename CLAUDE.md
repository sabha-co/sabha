# CLAUDE.md

Sabha is a Ruby on Rails chat application: Hotwire/Turbo views, ActionCable for real-time, Tailwind CSS v4 via `@tailwindcss/cli`, Importmap for JS. SQLite3 in production.

**Two deployment modes:** Self-hosted (default, single-tenant) and SaaS (multi-tenant via `activerecord-tenanted` gem, engine in `saas/`, enabled by `SAAS=true` or `tmp/saas.txt`). See @docs/multi-tenant/ for SaaS architecture details.

## Rails Code Quality Standards

IMPORTANT: Write it right the first time.

### RESTful Controllers
- **NEVER** add custom actions like `leave`, `activate`, `process` to controllers
- Map actions to standard CRUD: `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`
- If you need a "leave" action, it's `destroy` on a `MembershipsController`
- Create new controllers for new resources rather than adding non-REST actions

### Business Logic in Models
- **NEVER** put business logic in controllers — controllers only route and respond
- Controller actions should be ~5-10 lines max, calling model methods

### Model Method Conventions
- Methods ending in `!` raise exceptions on failure, never return symbols
- Return booleans or raise exceptions, never status symbols like `:success`, `:error`

```ruby
# BAD — Non-RESTful, returns symbols
class SettingsController < ApplicationController
  def leave
    case membership.leave!
    when :success then redirect_to root_path
    when :last_admin then redirect_back alert: "Can't leave"
    end
  end
end

# GOOD — RESTful, thin controller, exception-based
class MembershipsController < ApplicationController
  def destroy
    Current.membership.leave!
    redirect_to root_path
  rescue Membership::LastAdministratorError
    redirect_back alert: "Can't leave as last admin"
  end
end
```

### Callbacks
- Use **named methods**, not inline lambdas, for `after_*_commit` callbacks
- Keep callbacks as **separate declarations** — each gets its own error boundary in Rails
- **Don't move `deliver_later`/`send_*` to controllers** — models encapsulate delivery, controllers decide when

### `destroy_all_associated_records`
- When adding new associations, **update `destroy_all_associated_records`** in the model — some associations have `-> { active }` scopes so `dependent: :destroy` misses inactive records

### Don't Over-Extract
- Don't extract 20-25 line chunks into separate concern files — that's complexity theater
- Prefer namespace decomposition (`User::Role`, `Message::Searchable`) over `app/services/` bloat
- No form objects, policy gems, or service layers unless pain is real and measurable

## Key Domain Knowledge

### Room System (STI)
`Room` base class with: `Rooms::Open`, `Rooms::Closed`, `Rooms::Direct`, `Rooms::Thread` (tied to a parent message)

### Soft Deletion
Messages, Rooms, Memberships use `Deactivatable` concern (`active` boolean). Boost and Bookmark are hard-deleted.

### Mentions
Stateless for real-time, persistent for history. No mentions table — parsed from ActionText body HTML via `Message::Mentionee`. `Notification` records power the Activity tab and unread badges. `@everyone` uses `mentions_everyone` flag on messages table.

### Authentication
- **Self-hosted:** Password or email OTP (`AuthToken`), `Session` model, `Current.user`/`Current.session`/`Current.account`
- **SaaS:** `GlobalIdentity` + `AuthCode` + `GlobalSession` + `WorkspaceMembership`. `Current.user` derives from workspace membership.

## Development Commands

```bash
bin/setup                  # Install deps, prepare DB, build Tailwind
bin/dev                    # Start dev server
pnpm run build:css:watch   # Watch mode for CSS changes
```

### Testing
```bash
bin/rails test                           # Self-hosted tests
bin/rails test test/models/user_test.rb  # Single file
SAAS=true bin/rails test saas/test/      # SaaS test suite
```

After implementing changes, run the relevant test suite to verify. For SaaS changes, run both.

### SaaS Dual Database Setup
- **Untenanted (PostgreSQL):** `GlobalIdentity`, `Workspace`, `WorkspaceMembership`, `GlobalSession`. Models inherit from `UntenantedRecord`. Migrations in `saas/db/untenanted_migrate/`, schema in `saas/db/untenanted_schema.rb`.
- **Tenanted (SQLite per workspace):** All app models (`User`, `Room`, `Message`, etc.) inherit from `ApplicationRecord`. Each workspace gets its own SQLite database at `storage/{env}/workspaces/{tenant_id}/main.sqlite3`. Standard migrations in `db/migrate/`.

### Database Migrations
```bash
bin/rails db:migrate
```

IMPORTANT: After `db:migrate`, ALWAYS also run:
```bash
SAAS=true bin/rails db:migrate:primary    # Tenanted databases
SAAS=true bin/rails db:migrate:untenanted # Only if migration touches untenanted tables
```

### SaaS Mode
```bash
bin/rails saas:enable && bundle install && bin/rails saas:setup  # Enable
bin/rails saas:disable && bundle install                         # Disable
```

When updating gems in `Gemfile`, also run `BUNDLE_GEMFILE=Gemfile.saas bundle install` to keep lockfiles in sync.

### Tailwind CSS
Source: `app/javascript/entrypoints/application.css` → Output: `app/assets/builds/tailwind.css`. Compiled by `@tailwindcss/cli` via pnpm. No Vite, no bundler.

## Context Management

When compacting, preserve the list of modified files, failing test output, and any architectural decisions made during the session.

## UI/Styling Guidelines

When making UI/styling changes, always ask for specific color values, backgrounds, and visual references before implementing. Show a summary of proposed changes before editing CSS/view files.
