# CLAUDE.md

Sabha is a Ruby on Rails chat application: Hotwire/Turbo views, AnyCable (a separate Go WebSocket server) for real-time, Tailwind CSS v4 via `@tailwindcss/cli`, Importmap for JS. SQLite3 in production.

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
# (real code: app/controllers/rooms/memberships_controller.rb)
class Rooms::MembershipsController < ApplicationController
  def destroy
    @room.accept_leave!(Current.user)
    redirect_to root_url, notice: "You left #{@room.name}"
  rescue Membership::LastVisibleMemberError
    redirect_back fallback_location: room_url(@room),
                  alert: "You're the last member. Delete the room instead."
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

### Database Portability (keep it Postgres-ready)
SQLite is the default engine, but the app is deliberately kept PostgreSQL-compatible so a future self-hosted Postgres option is a deployment change, not a code rewrite (the SaaS untenanted DB already runs Postgres). Write new SQL to run on **both** engines:
- Prefer Arel / adapter-agnostic ActiveRecord over raw SQL. When raw SQL is unavoidable, keep it portable — `matches` (renders `ILIKE`/`LIKE`) not a bare `LIKE`, boolean `TRUE`/`FALSE` not `1`/`0`, a `CASE` clamp not scalar `MAX`/`GREATEST`, and branch on `connection.adapter_name` only where no common form exists (`strpos`/`instr`, `jsonb ->>`/`json_extract`).
- Full-text search is engine-specific and owned by `Message::SearchIndex` (FTS5 on SQLite, a `tsvector` column on Postgres). Route all index reads/writes through it — don't hardcode `message_search_index`. The index lives outside `db/schema.rb`; provision it via `Message::SearchIndex.ensure!`, never a migration.

## Key Domain Knowledge

### Room System (STI)
`Room` base class with six subclasses:

- **Sidebar rooms** — `Rooms::Open` (browsable, joinable, optional `auto_join`), `Rooms::Closed` (explicit membership), `Rooms::Forum` (community-wide, `auto_join` forced on; renders a **post gallery**, not a message stream)
- **DMs** — `Rooms::Direct`, one per unique member set via `members_hash`
- **Sub-rooms** (`SUB_ROOM_TYPES`) — `Rooms::Thread` (tied to a parent message) and `Rooms::Post` (tied to a forum). Both delegate `viewable_by?` to their parent, so access is inherited rather than re-declared.

`Rooms::AccessController#update` converts Open ↔ Closed in place via `becomes!`.

### Soft Deletion
Messages, Rooms, Memberships use `Deactivatable` concern (`active` boolean). Boost and Bookmark are hard-deleted.

### Mentions
Stateless for real-time, persistent for history. No mentions table — parsed from ActionText body HTML via `Message::Mentionee`. `Notification` records power the Activity tab and unread badges. `@everyone` uses `mentions_everyone` flag on messages table.

### Authentication
- **Self-hosted:** Password or email OTP (`AuthToken`), `Session` model, `Current.user`/`Current.session`/`Current.account`
- **SaaS:** `GlobalIdentity` + `AuthCode` + `GlobalSession` + `WorkspaceMembership`. `Current.user` derives from workspace membership.

### Real-time (AnyCable)
Sabha uses **AnyCable** as its real-time transport — a required runtime dependency, not the in-process ActionCable adapter. How it's wired here:

- **Transport:** `anycable-go` is a separate process that terminates every WebSocket connection and calls back into Rails over HTTP RPC at `/_anycable`. All environments use the `any_cable` adapter in `config/cable.yml` (only `test` uses `test`) — the in-process/redis fallback was removed, so Rails is never the WebSocket server.
- **Process topology:** dev starts it via `bin/dev` (`Procfile.dev`, port 8080). Both deployment modes run `anycable/anycable-go` as a Kamal accessory routed at `/cable` with RPC pointed back at the Rails service — self-hosted via `config/deploy.yml`, SaaS via `config/deploy.multitenant.yml`. A self-hosted install needs the sidecar too; there is no Rails-only mode.
- **Broker:** the **in-memory broker** backs presence and stream history (presence TTL set explicitly to 45s — it bounds how long push stays suppressed after a socket dies, so it must clear the client's worst-case reconnect). State is per-node, so we run a single `anycable-go` replica.
- **Presence reads:** push gating asks the broker who's watching (`Room::PresenceSet` → `GET /api/presence/:stream/users`) rather than the `connected_at` column. The API secret is derived: `HMAC-SHA256(ANYCABLE_SECRET, "api-cable")`. An unreachable broker degrades to the DB signal rather than dropping pushes.
- **Auth:** sockets are identified by a JWT so reconnects skip the connect RPC.
- **Channels** are ordinary ActionCable classes; presence uses `AnyCable::Rails::Channel::Presence` (`PresenceChannel`).
- **Config:** `config/anycable.yml` (JWT/stream secrets) + `config/cable.yml`. Docs: https://docs.anycable.io (full text: https://docs.anycable.io/llms-full.txt).

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
- **Tenanted (SQLite per workspace):** All app models (`User`, `Room`, `Message`, etc.) inherit from `ApplicationRecord`. Each workspace gets its own SQLite database at `storage/workspaces/{env}/{tenant}/db/main.sqlite3`. Standard migrations in `db/migrate/`.

### Database Migrations
```bash
bin/rails db:migrate                       # Self-hosted only
SAAS=true bin/rails db:migrate:primary     # SaaS (auto-chains untenanted)
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

## Design Context

### Users
Community-oriented chat. Users are members of online communities — hobbyist groups, open-source projects, interest-based collectives. They want a space that feels owned and personal, not corporate. They're chatting throughout the day, catching up on threads, and participating in group conversations.

### Brand Personality
**Warm, simple, reliable.** Sabha should feel like a well-made tool you trust — friendly and approachable without being cute, opinionated without being rigid. Think 37signals: clear opinions, no feature bloat, design that gets out of the way.

### Aesthetic Direction
- **Visual tone:** Clean, minimal, human. Generous whitespace. No visual noise.
- **Reference:** Campfire / HEY — distinctive, opinionated design language with personality baked into restraint rather than decoration.
- **Anti-references:** Discord feature overload, generic SaaS dashboards, dark-themed gamer aesthetics.
- **Theme:** Light and dark mode via OKLch tokens. Light mode is the primary experience.
- **Color:** Indigo is the default brand accent for interactive elements (links, selection, primary actions), with five selectable workspace accents (indigo/ink/forest/rust/plum) bound via `[data-accent]`. Warm earth tones for avatars/identity, cool grays for structure. Red reserved for destructive/negative actions. Tokens are declared once in `app/assets/stylesheets/application/colors.css` (primitives → semantic → scopes); components read only the semantic `--color-*` layer.
- **Typography:** Self-hosted Instrument Sans for UI and body, JetBrains Mono for code, each over a system-font fallback stack (see `app/assets/stylesheets/application/base.css`). 6-level size scale. Let the text breathe.

### Design Principles
1. **Clarity over cleverness** — Every element should be immediately understandable. No mystery meat navigation, no hidden features behind gestures.
2. **Warmth through restraint** — Personality comes from thoughtful defaults and subtle touches (avatar colors, spacing, transitions), not from decoration or illustration.
3. **Content-first** — Messages are the product. UI chrome should be minimal and recede. The conversation is always the hero.
4. **Responsive by nature** — The sidebar defaults to a dark contrast surface in both themes, with the warm-light "bench edge" available as the per-device Match preference. It docks left ≥1280px, collapses to a 60px icon rail from 834–1279px (expanding over the content on demand), and becomes a drawer over a scrim below 834px. Design for every state from the start, not as an afterthought.
5. **Accessible by default** — WCAG AA contrast, keyboard navigation, screen reader support, `max(16px, 1em)` inputs. Accessibility is not a feature, it's the baseline.
