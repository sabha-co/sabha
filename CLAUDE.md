# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

Sabha is a Ruby on Rails chat application combining:
- **Traditional Rails views + Hotwire/Turbo** for the core chat interface (real-time messaging)
- **ActionCable (WebSockets)** for real-time updates across all chat features
- **Vite** for modern frontend asset processing (Tailwind CSS v4)
- **Importmap** for JavaScript module loading (Stimulus controllers)

**Deployment Modes:**
- **Self-hosted (default):** Single-tenant, deploy via Kamal or Docker Compose
- **SaaS mode:** Multi-tenant with database-per-workspace isolation via `activerecord-tenanted` gem

**SaaS Engine (`saas/` folder):**
The multi-tenant layer is implemented as a Rails engine in `saas/`:
- `saas/lib/sabha/saas/engine.rb` - Engine configuration, routes, and middleware
- `saas/app/models/` - Untenanted models (GlobalIdentity, Workspace, WorkspaceMembership)
- `saas/app/controllers/saas/` - Controllers inheriting from `Saas::BaseController`
- `saas/config/initializers/tenanting/` - Tenant resolution, path rewriting, Turbo/Storage hooks
- Enabled via `Sabha.saas?` check (set by `SAAS=true` env var or `tmp/saas.txt` file)
- Uses `Gemfile.saas` which extends the base `Gemfile`

## Core Domain Models

### Room System (Single Table Inheritance)
- `Room` - Base class with STI types:
  - `Rooms::Open` - Public rooms accessible to all members
  - `Rooms::Closed` - Private invite-only rooms
  - `Rooms::Direct` - 1-on-1 or group direct messages
  - `Rooms::Thread` - Special rooms tied to a parent message (threaded discussions)

### Messaging & Engagement
- `Message` - Rich text content via ActionText, with attachments, mentions, sounds
- `Membership` - Join table between Users and Rooms with involvement levels (invisible, nothing, mentions, everything)
- `Boost` - Message reactions/reposts (similar to retweets)
- `Bookmark` - Save messages for later reference
- Messages use soft deletion (`active` boolean) - deleted messages marked inactive but preserved in database

### Authentication (Dual Strategy)
**Self-hosted mode:**
- **Passwordless (Email OTP)**: `AuthToken` model generates 6-digit codes sent via email
- **Traditional Password**: Standard `has_secure_password` with password reset tokens
- `Session` - Tracks browser, IP, platform for multi-device support
- Email verification required for new users (`verified_at` timestamp)

**SaaS mode:**
- `GlobalIdentity` - Cross-workspace user identity (email only, no password)
- `AuthCode` - OTP codes for GlobalIdentity (parallels AuthToken)
- `GlobalSession` - Cross-workspace session with `global_session_token` cookie
- `WorkspaceMembership` - Links GlobalIdentity to workspace tenant

## Key Architectural Patterns

### Concerns for Shared Behavior
- `Deactivatable` - Soft deletion with `active` scope
- `Mentionable` - Entities that can be @mentioned in messages
- `Searchable` - Full-text search with SQLite FTS5
- `Connectable` - Tracks WebSocket connection state for memberships
- `Avatar` - User avatar management
- `User::DicebearAvatar` - Auto-generated avatars via DiceBear API for users without photos

### Current Context
```ruby
# Self-hosted mode:
Current.user      # Current user (from session)
Current.session   # Session record
Current.account   # Workspace settings (singleton)
Current.request   # HTTP request object

# SaaS mode (additional):
Current.global_session        # Cross-workspace GlobalSession
Current.global_identity       # GlobalIdentity (via global_session)
Current.workspace_membership  # Link between identity and workspace
Current.workspace             # Current Workspace record (lazy-loaded)
# Current.user derives from workspace_membership.user in SaaS mode
```

### Query Objects
Complex queries are extracted into query objects in `app/models/`:
- `Inbox::ActivityQuery`, `Inbox::ThreadsQuery`, `Inbox::BookmarksQuery`, `Inbox::MessagesQuery` - Inbox filtering
- `SidebarMemberships` - Sidebar room list queries

### Turbo Streams for Real-time Updates
Messages, room updates, and notifications broadcast via:
```ruby
broadcast_append_to room, :messages, partial: "messages/message"
broadcast_replace_to room, :unread_count, target: "unread-#{room.id}"
```

## Rails Code Quality Standards

**Write it right the first time - don't rely on reviews to catch these:**

### RESTful Controllers
- **NEVER** add custom actions like `leave`, `activate`, `process` to controllers
- Map actions to standard CRUD: `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`
- If you need a "leave" action, it's `destroy` on a `MembershipsController`
- If you need a "publish" action, it's `create` on a `PublicationsController`
- Create new controllers for new resources rather than adding non-REST actions

### Business Logic in Models
- **NEVER** put business logic in controllers - controllers only route and respond
- Auth code creation, email sending, state changes → all belong in models
- Controller actions should be ~5-10 lines max, calling model methods
- If you're writing a `case` statement in a controller parsing return values, refactor

### Model Method Conventions
- Methods ending in `!` should raise exceptions on failure, not return symbols
- Return booleans or raise exceptions, never status symbols like `:success`, `:error`
- Let ActiveRecord validations speak - don't reinvent error handling

### Example Patterns

```ruby
# BAD - Non-RESTful action, business logic in controller
class SettingsController < ApplicationController
  def leave
    case membership.leave!
    when :success then redirect_to root_path
    when :last_admin then redirect_back alert: "Can't leave"
    end
  end
end

# GOOD - RESTful, thin controller
class MembershipsController < ApplicationController
  def destroy
    Current.membership.leave!
    redirect_to root_path
  rescue Membership::LastAdministratorError
    redirect_back alert: "Can't leave as last admin"
  end
end
```

```ruby
# BAD - Returns symbols
def leave!
  return :last_admin if last_admin?
  destroy!
  :success
end

# GOOD - Raises exceptions
def leave!
  raise LastAdministratorError if last_admin?
  destroy!
end
```

### Callbacks
- Use **named methods**, not inline lambdas, for `after_*_commit` callbacks — easier to read and debug
- Keep callbacks as **separate declarations** — each `after_create_commit` gets its own error boundary in Rails. Don't collapse into a single orchestrator method
- `before_validation` and `before_save` callbacks for data transformation are fine (score 5/5)
- `after_create_commit` callbacks for side effects (broadcasts, notifications) are acceptable Rails
- **Don't move model `deliver_later`/`send_*` methods to controllers** — models encapsulate *how* delivery happens, controllers decide *when*. Scattering mailer calls across controllers breaks DRY

### Tables with `id: false` (Join Tables)
- The `mentions` table uses `id: false` (composite key: `message_id` + `user_id`)
- **ALWAYS use `dependent: :delete_all`** (not `dependent: :destroy`) on associations pointing to `id: false` tables
- `dependent: :destroy` tries to delete records by primary key — generates broken SQL on keyless tables: `DELETE FROM "table" WHERE "table"."" IS NULL`
- When adding new associations to users/rooms/messages, **update `destroy_all_associated_records`** in the model — soft-deletion scopes mean `dependent: :destroy` misses inactive records

### Don't Over-Extract
- 453 lines is not a god object for a chat app User model — users do a lot of things
- Don't extract 20-25 line chunks into separate concern files — that's complexity theater
- The test for extraction: "Does this make the code genuinely easier to understand?"
- Prefer namespace decomposition (`User::Role`, `Message::Searchable`) over `app/services/` directory bloat
- No form objects, policy gems, or service layers unless pain is real and measurable

## Development Commands

### Setup
```bash
bin/setup  # Installs gems, pnpm packages, prepares DB, builds Tailwind once
```

### Running Locally
```bash
bin/dev    # Start dev server (jobs run in web process)
bin/boot   # Full stack: web + redis + workers (production-like)
```

Vite runs automatically via vite_rails with autoBuild: true.

### SaaS Mode (Multi-Tenant)

Sabha supports two deployment modes:
- **Self-host (default)**: Single-tenant, one workspace per installation
- **SaaS mode**: Multi-tenant with database-per-workspace isolation

```bash
# Check current mode
bin/rails saas:status

# Enable SaaS mode (creates tmp/saas.txt, uses Gemfile.saas)
bin/rails saas:enable
bundle install
bin/rails saas:setup   # Creates default workspace (ID 1000001)
bin/dev

# Disable SaaS mode (removes tmp/saas.txt, uses regular Gemfile)
bin/rails saas:disable
bundle install
bin/dev

# Temporary SaaS mode (single session only)
SAAS=true bin/dev
```

**Important**: After switching modes, always run `bundle install` to use the correct Gemfile.

**Important**: When updating gems in `Gemfile` (e.g. bumping the Rails ref), you must also run `BUNDLE_GEMFILE=Gemfile.saas bundle install` to keep the SaaS lockfile in sync.

**SaaS Development Workflow:**
```bash
# Initial setup (after enabling SaaS mode)
bin/setup                    # Runs saas:setup automatically

# Workspace management
bin/rails workspace:list                          # List all workspaces
bin/rails workspace:create[name,email]            # Create new workspace
bin/rails workspace:destroy[1000001]              # Destroy workspace
bin/rails workspace:info[1000001]                 # Show workspace details

# Access URLs
# Landing page: http://localhost:3000/
# Workspace:    http://localhost:3000/1000001/

# Reset everything (destructive)
bin/rails saas:reset
```

**Running Tests:**
```bash
# Self-hosted tests
bin/rails test

# SaaS tests (separate test suite)
SAAS=true bin/rails test saas/test/
```

SaaS mode adds:
- `activerecord-tenanted` gem for per-workspace SQLite databases
- Path-based workspace routing (`/1000001/rooms/general`)
- `GlobalIdentity` model for cross-workspace authentication
- `AuthCode` model for OTP codes (parallels `AuthToken` in self-hosted)
- `Workspace` model in untenanted database
- Workspace selector sidebar for users with multiple workspaces

See `docs/multi-tenant/` for detailed SaaS architecture documentation (internal reference only - not for public users).

### Tailwind CSS
```bash
# Tailwind is processed by Vite from app/frontend/entrypoints/application.css
# Automatically rebuilt during development - no separate command needed
```

### Testing
```bash
bin/rails test                          # Run all tests (self-hosted mode)
bin/rails test test/models/user_test.rb # Single test file
bin/rails test:system                   # Browser-based system tests
```

**SaaS Mode Tests:**
```bash
# Run SaaS test suite
SAAS=true bin/rails test saas/test/

# Run a single SaaS test file
SAAS=true bin/rails test saas/test/models/workspace_test.rb
```

SaaS tests are located in `saas/test/` and test the multi-tenant infrastructure:
- `saas/test/models/` - GlobalIdentity, GlobalSession, Workspace, WorkspaceMembership, AuthCode
- `saas/test/controllers/saas/` - Sessions, registrations, workspaces, profiles, landing, auth codes
- `saas/test/fixtures/` - Fixtures for untenanted models

Test framework: Minitest with mocha (mocking), webmock (HTTP stubbing), capybara/cuprite (system tests)

**Testing approach:** Real database. Uses vanilla Rails setup of loading fixtures once, then using per-test transactions to rollback changes. No mocking of database interactions.

### Database
```bash
bin/rails db:migrate          # Run migrations
bin/rails db:reset            # Drop, create, migrate, seed
bin/rails db:rollback         # Rollback last migration
bin/rails console             # Rails console for debugging
```

**IMPORTANT: After running `bin/rails db:migrate`, ALWAYS also migrate SaaS databases:**
```bash
SAAS=true bin/rails db:migrate:primary    # Tenanted (per-workspace SQLite) databases
SAAS=true bin/rails db:migrate:untenanted # Untenanted (PostgreSQL) database — only if migration touches untenanted tables
```
Do NOT forget this step. Tenanted migrations must be applied to both self-hosted and SaaS databases.

Database: SQLite3 with FTS5 full-text search support

### Deployment (Kamal)
```bash
kamal setup           # Initial server setup (builds image, starts services)
kamal deploy          # Zero-downtime deployment
kamal app exec 'bin/rails console'  # Run console on production
kamal app logs        # View application logs
kamal envify          # Show environment variables being used

# SaaS (multitenant) deploy — source env first since Kamal needs vars for ERB templates
set -a && source .env.multitenant && set +a && kamal deploy -d multitenant
```

## Frontend Architecture

### Build Tools
- **Vite** - Used ONLY for Tailwind CSS v4 (requires build step). Not used for JavaScript bundling.
- **Importmap** - Handles all JavaScript/Stimulus controllers. No bundling, direct ESM imports.

### Directory Structure
```
app/frontend/
├── entrypoints/
│   ├── application.js      # Just imports CSS, no app logic
│   └── application.css     # Tailwind v4 styles + theme
└── controllers/            # Stimulus controllers (loaded via importmap, not Vite)
```

### Rails Views
- Main layout: `app/views/layouts/application.html.erb`
- Partials organized by feature: `messages/`, `rooms/`, `inboxes/`, `users/sidebars/`

## Real-time Features (ActionCable)

### Channels
- `RoomChannel` - Message broadcasts to room subscribers
- `PresenceChannel` - Online user tracking
- `RoomListChannel` - Sidebar room list updates
- `UserUnreadRoomsChannel` - User-scoped unread notifications
- `TypingNotificationsChannel` - "User is typing..." indicators
- `InboxActivityChannel` & `InboxThreadsChannel` - Inbox real-time updates

### Connection
Authentication via signed cookie in `ApplicationCable::Connection`:
```ruby
# Self-hosted: Uses session_token cookie → Session → User
# SaaS mode:   Uses global_session_token cookie → GlobalSession → WorkspaceMembership → User
#              Gem's around_command :with_tenant wraps all channel commands
self.current_user = user  # Set after cookie-based lookup
```

## Background Jobs

Uses Solid Queue (SQLite-backed) for background processing:
- `Room::PushMessageJob` - Web push notifications for new messages

**SaaS mode:** The `activerecord-tenanted` gem automatically serializes `current_tenant` with job payloads and restores it during `perform`. GlobalID parameters also include tenant context.

### Production Startup (`bin/boot`)
```
bin/boot → reads Procfile → spawns 3 processes:
├── web: bin/start-app (db:prepare + Puma)
├── redis: redis-server
└── workers: rake solid_queue:start
```

### Configuration
- `config/queue.yml` - Worker/dispatcher configuration (threads, polling interval)
- `config/recurring.yml` - Scheduled/recurring jobs
- Queue database: Separate SQLite database (`storage/db/*_queue.sqlite3`)

## Important Configuration

### Environment Variables
Core branding (see `.env.sample` and `BRANDING.md`):
- `APP_NAME` - Application name displayed throughout UI
- `APP_HOST` - Primary domain for the application
- `SUPPORT_EMAIL` - Support contact email
- `MAILER_FROM_NAME` / `MAILER_FROM_EMAIL` - Transactional email sender

Required for production:
- `SECRET_KEY_BASE` - Rails encryption key
- `RESEND_API_KEY` - Email delivery via Resend
- `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` - Web push notifications

Optional features:
- `JOB_CONCURRENCY` - Number of Solid Queue worker processes
- `SOLID_QUEUE_IN_PUMA=true` - Run jobs inside Puma instead of separate workers
- `DICEBEAR_ENABLED=true` - Enable auto-generated avatars for users without photos
- `DICEBEAR_HOST` - DiceBear API host (default: api.dicebear.com, must be HTTPS in production)
- `DICEBEAR_STYLE` - Avatar style (default: thumbs)

### Key Initializers
- `content_security_policy.rb` - CSP frame ancestors (iframe embedding)
- `resend.rb` - Custom ActionMailer delivery via Resend API
- `web_push.rb` - VAPID-based web push notification setup
- `sqlite3.rb` - SQLite production optimizations (busy timeout, journal mode)
- `dicebear.rb` - DiceBear avatar generation configuration

**SaaS mode initializers** (`saas/config/initializers/tenanting/`):
- `tenant_resolver.rb` - Extracts tenant from SCRIPT_NAME
- `path_rewriter.rb` - Middleware moves workspace prefix to SCRIPT_NAME
- `turbo.rb` - Ensures Turbo broadcasts include workspace prefix
- `active_storage.rb` - Sets URL options with script_name for attachments
- `logging.rb` - Adds tenant tags to Rails and SQL logs

### Routes Structure
**Self-hosted mode:**
- Conditional root routes (authenticated → `welcome#show`, unauthenticated → redirect to sign-in)
- Nested resources: `/rooms/:room_id/messages/:id`

**SaaS mode:**
- Workspace prefix in all URLs: `/{workspace_id}/rooms/general` (e.g., `/1000001/rooms/general`)
- PathRewriter middleware moves prefix to SCRIPT_NAME, URL helpers auto-include it
- Global routes without prefix: `/session/new`, `/workspaces`, `/join`
- SaaS controllers in `saas/app/controllers/saas/` inherit from `Saas::BaseController`

## Testing Guidelines

### Test Structure
```
test/                    # Self-hosted tests (bin/rails test)
├── controllers/         # Controller unit tests
├── models/              # Model unit tests
├── system/              # Full-stack Capybara tests (browser-based)
├── channels/            # ActionCable channel tests
├── jobs/                # Background job tests
└── fixtures/            # Test data

saas/test/               # SaaS tests (SAAS=true bin/rails test saas/test/)
├── models/              # GlobalIdentity, Workspace, WorkspaceMembership, etc.
├── controllers/saas/    # SaaS controller tests
└── fixtures/            # Untenanted model fixtures
```

### Test Helpers
- `SessionTestHelper` - Sign in/out helpers for tests
- `MentionTestHelper` - Create mentions in messages
- `TurboTestHelper` - Test Turbo Stream broadcasts
- WebMock enabled for HTTP stubbing in tests
- Authentication in tests: Set `Current.account.update!(auth_method: "password")` or `"otp"` as needed

## Common Development Tasks

### Adding a New Message Feature
1. Add logic to `Message` model or create concern in `app/models/concerns/message/`
2. Update `MessagesController` for user interactions
3. Broadcast changes via Turbo Stream in model callback or controller
4. Add partial in `app/views/messages/` for rendering
5. Subscribe to `RoomChannel` if real-time updates needed

### Adding a New Room Type
1. Create subclass of `Room` in `app/models/rooms/`
2. Preload in `config/initializers/preload_room_subclasses.rb`
3. Add routing constraints if needed
4. Update `RoomsController#show` for type-specific rendering

### Adding ActionCable Channel
1. Generate: `bin/rails generate channel FeatureName`
2. Implement `#subscribed` and `#receive` in channel class
3. Create JavaScript subscription in `app/frontend/entrypoints/application.js`
4. Broadcast from model/controller: `ActionCable.server.broadcast "channel_name", data`

### Customizing Branding
1. **Admin Settings UI** (`/account/edit` - administrators only):
   - Authentication method (password/OTP) - stored in `accounts.auth_method`
   - Permission toggles - stored in `accounts.settings` JSON column via `has_json`
2. **Environment Variables** (`.env` or `.kamal/secrets`):
   - APP_NAME, SUPPORT_EMAIL, THEME_COLOR, BACKGROUND_COLOR, etc. (see `config/initializers/branding.rb`)
3. Visual assets replaced in `app/assets/images/logos/` and `app/assets/images/icons/`
4. Branding accessed via `Branding` module throughout app (delegates to `Rails.configuration.x.branding`)

## Database Schema Notes

- **SQLite3** in production (optimized for single-server deployments)
- Schema format: Ruby (`db/schema.rb`), using `create_virtual_table` for FTS5
- Migrations in `db/migrate/` with schema in `db/schema.rb`
- Full-text search on messages via `messages_fts` virtual table

**SaaS mode databases:**
- PostgreSQL `sabha_untenanted_{env}` - GlobalIdentity, Workspace, WorkspaceMembership, GlobalSession (platform-owned, managed separately)
- `storage/{env}/workspaces/{tenant_id}/main.sqlite3` - Per-workspace data (User, Room, Message, etc.)
- Untenanted migrations in `saas/db/untenanted_migrate/`, schema in `saas/db/untenanted_schema.rb`
- Models inherit from `UntenantedRecord` (PostgreSQL) or `ApplicationRecord` (tenanted SQLite)
- Database config: `config/database.yml` delegates to `config/database.sqlite.yml` (self-hosted) or `saas/config/database.yml` (SaaS)

## Deployment Architecture

- **Kamal/Docker self-hosting**: Thruster provides HTTP/2, automatic TLS (Let's Encrypt), caching, and compression
- **Sabha Cloud**: Caddy handles TLS/HTTP2, set `SKIP_THRUSTER=true` to run Puma directly
- SQLite database persisted in mounted volume `/disk/sabha/`
- Redis container for ActionCable pub/sub
- Automated SSL via Thruster (self-host) or Caddy (Sabha Cloud) with health checks at `/up`
- GitHub Actions auto-deploys on push to `master` (see `.github/workflows/deploy_with_kamal.yml`)

## Special Features (from Small Bets fork)

- **Activity Tab** - Dedicated inbox for @mentions and DMs
- **Bookmarks** - Save messages for later
- **Reboost** - One-click message resharing
- **Stats Page** - Community leaderboards and analytics
- **Soft Deletion** - Messages marked inactive but preserved
- **Enhanced Bot API** - Webhooks and DM initiation for bots
- use docker/caddy based deployment as default.

## UI/Styling Guidelines

When making UI/styling changes, always ask for specific color values, backgrounds, and visual references before implementing. Show a summary of proposed changes before editing CSS/view files.