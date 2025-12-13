# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

Campfire-CE is a Ruby on Rails chat application combining:
- **Traditional Rails views + Hotwire/Turbo** for the core chat interface (real-time messaging)
- **ActionCable (WebSockets)** for real-time updates across all chat features
- **Vite** for modern frontend asset processing (Tailwind CSS v4)
- **Importmap** for JavaScript module loading (Stimulus controllers)

## Core Domain Models

### Room System (Single Table Inheritance)
- `Room` - Base class with STI types:
  - `Rooms::Open` - Public rooms accessible to all members
  - `Rooms::Closed` - Private invite-only rooms
  - `Rooms::Direct` - 1-on-1 or group direct messages
  - `Rooms::Thread` - Special rooms tied to a parent message (threaded discussions)
- Rooms are identified by slugs for clean URLs (`/general` instead of `/rooms/1`)
- See `RoomSlugConstraint` in routes.rb for slug routing logic

### Messaging & Engagement
- `Message` - Rich text content via ActionText, with attachments, mentions, sounds
- `Membership` - Join table between Users and Rooms with involvement levels (invisible, nothing, mentions, everything)
- `Boost` - Message reactions/reposts (similar to retweets)
- `Bookmark` - Save messages for later reference
- Messages use soft deletion (`active` boolean) - deleted messages marked inactive but preserved in database

### Authentication (Dual Strategy)
- **Passwordless (Email OTP)**: `AuthToken` model generates 6-digit codes sent via email
- **Traditional Password**: Standard `has_secure_password` with password reset tokens
- `Session` - Tracks browser, IP, platform for multi-device support
- Email verification required for new users (`verified_at` timestamp)

### Payment System (Optional Gumroad Integration)
- `GumroadAPI` - Wrapper around Gumroad REST API for paid memberships
- `Webhook` & `WebhookEvent` - Handles Gumroad sale/refund webhooks
- `Purchaser` - Tracks user purchases
- Controlled by `ENV["GUMROAD_ON"]` - can run as free community if disabled

## Key Architectural Patterns

### Concerns for Shared Behavior
- `Deactivatable` - Soft deletion with `active` scope
- `Mentionable` - Entities that can be @mentioned in messages
- `Searchable` - Full-text search with SQLite FTS5
- `Connectable` - Tracks WebSocket connection state for memberships
- `Avatar` - User avatar management

### Current Context
```ruby
Current.user      # Thread-safe request context
Current.session   # Available throughout application
```

### Turbo Streams for Real-time Updates
Messages, room updates, and notifications broadcast via:
```ruby
broadcast_append_to room, :messages, partial: "messages/message"
broadcast_replace_to room, :unread_count, target: "unread-#{room.id}"
```

## Development Commands

### Setup
```bash
bin/setup  # Installs gems, npm packages, prepares DB, builds Tailwind once
```

### Running Locally
```bash
bin/rails server  # Start development server (port 3000)
# Vite runs automatically via vite_rails with autoBuild: true
```

### Tailwind CSS
```bash
# Tailwind is processed by Vite from app/frontend/entrypoints/application.css
# Automatically rebuilt during development - no separate command needed
```

### Testing
```bash
bin/rails test                          # Run all tests
bin/rails test test/models/user_test.rb # Single test file
bin/rails test:system                   # Browser-based system tests
```
Test framework: Minitest with mocha (mocking), webmock (HTTP stubbing), capybara/selenium (system tests)

### Database
```bash
bin/rails db:migrate          # Run migrations
bin/rails db:reset            # Drop, create, migrate, seed
bin/rails db:rollback         # Rollback last migration
bin/rails console             # Rails console for debugging
```
Database: SQLite3 with FTS5 full-text search support

### Deployment (Kamal)
```bash
kamal setup           # Initial server setup (builds image, starts services)
kamal deploy          # Zero-downtime deployment
kamal app exec 'bin/rails console'  # Run console on production
kamal app logs        # View application logs
kamal envify          # Show environment variables being used
```

## Frontend Architecture

### Directory Structure
```
app/frontend/
├── entrypoints/
│   ├── application.js      # Stimulus controllers for Rails views
│   └── application.css     # Tailwind v4 styles
└── controllers/            # Stimulus controllers
```

### Rails Views
- Main layout: `app/views/layouts/application.html.erb`
- Uses Vite for CSS and importmap for JavaScript
- Partials organized by feature: `messages/`, `rooms/`, `inboxes/`, `users/sidebars/`

## Real-time Features (ActionCable)

### Channels
- `RoomChannel` - Message broadcasts to room subscribers
- `PresenceChannel` - Online user tracking
- `RoomListChannel` - Sidebar room list updates
- `UnreadRoomsChannel` - Unread count broadcasts
- `TypingNotificationsChannel` - "User is typing..." indicators
- `InboxMentionsChannel` & `InboxThreadsChannel` - Inbox real-time updates

### Connection
Authentication via cookie-based session in `ApplicationCable::Connection`:
```ruby
self.current_user = User.find_by(id: request.session[:user_id])
```

## Background Jobs

Uses Resque (Redis-backed) for background processing:
- `Room::PushMessageJob` - Web push notifications for new messages
- `UnreadMentionsNotifierJob` - Daily email digest of unread mentions/DMs
- `Gumroad::ImportUserJob` - Process Gumroad purchase webhooks

Scheduled jobs via rufus-scheduler (see `config/initializers/rufus_scheduler.rb`)

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
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` - File storage (S3)
- `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` - Web push notifications
- `WEBHOOK_SECRET` - Webhook security token

Optional features:
- `GUMROAD_ON=true` - Enable payment gating
- `GUMROAD_ACCESS_TOKEN` - Gumroad API access

### Key Initializers
- `content_security_policy.rb` - CSP frame ancestors (iframe embedding)
- `resend.rb` - Custom ActionMailer delivery via Resend API
- `web_push.rb` - VAPID-based web push notification setup
- `sqlite3.rb` - SQLite production optimizations (busy timeout, journal mode)
- `gumroad.rb` - Payment integration configuration

### Routes Structure
- Top-level room slug routing via `RoomSlugConstraint`
- Conditional root routes (authenticated → `welcome#show`, unauthenticated → `marketing#show`)
- Nested resources: `/rooms/:room_id/messages/:id`
- Webhook endpoints: `POST /webhooks/gumroad/users/:webhook_secret`

## Testing Guidelines

### Test Structure
```
test/
├── controllers/  # Controller unit tests
├── models/       # Model unit tests
├── system/       # Full-stack Capybara tests (browser-based)
├── channels/     # ActionCable channel tests
├── jobs/         # Background job tests
└── fixtures/     # Test data
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
- Schema format: SQL (required for FTS5 full-text search extensions)
- Migrations in `db/migrate/` with schema in `db/schema.sql`
- Full-text search on messages via `messages_fts` virtual table

## Deployment Architecture

- **Kamal** orchestrates Docker-based zero-downtime deployments
- Single container runs Rails app + Thruster HTTP/2 proxy
- SQLite database persisted in mounted volume `/disk/campfire/`
- Redis container for ActionCable and Resque
- Automated SSL via Kamal proxy with health checks at `/up`
- GitHub Actions auto-deploys on push to `master` (see `.github/workflows/deploy_with_kamal.yml`)

## Special Features (from Small Bets fork)

- **Mentions Tab** - Dedicated inbox for all @mentions
- **Email Notifications** - Daily digest of unread mentions/DMs
- **Bookmarks** - Save messages for later
- **Reboost** - One-click message resharing
- **Stats Page** - Community leaderboards and analytics
- **Soft Deletion** - Messages marked inactive but preserved
- **Enhanced Bot API** - Webhooks and DM initiation for bots
- use docker/caddy based deployment as default.