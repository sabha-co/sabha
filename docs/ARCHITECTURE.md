# Sabha Architecture

Sabha is a real-time chat application built with Ruby on Rails, Hotwire, and SQLite. It supports two deployment modes: **self-hosted** (single-tenant) and **SaaS** (multi-tenant with database-per-workspace isolation).

[Visual architecture diagrams (Excalidraw)](https://excalidraw.com/#json=NROsXM5J3pIdiRL_1x9d_,5hRkehIds4KTPlnKqJG7SA)

---

## Table of Contents

- [System Overview](#system-overview)
- [Request Lifecycle](#request-lifecycle)
- [Domain Model](#domain-model)
- [Authentication](#authentication)
- [Real-Time Layer](#real-time-layer)
- [Frontend Architecture](#frontend-architecture)
- [Background Jobs](#background-jobs)
- [SaaS / Multi-Tenant](#saas--multi-tenant)
- [Database](#database)
- [Deployment](#deployment)
- [Key Dependencies](#key-dependencies)

---

## System Overview

```
                    ┌──────────────────────────────────────────────────────┐
                    │  Server (single host)                                │
                    │                                                      │
  Browser ─HTTPS──▶ │  Kamal Proxy / Caddy (:443)                        │
                    │      │             │                                  │
                    │      │ /cable      │ /*                               │
                    │      ▼             ▼                                  │
                    │  ┌──────────┐  ┌───────────────────────────────────┐ │
                    │  │ AnyCable │  │ Web Container                     │ │
                    │  │ Go :8080 │  │                                   │ │
                    │  │          │  │  Puma :3000                       │ │
                    │  │ HTTP RPC─┼──┼──▶ Rails App (/_anycable)        │ │
                    │  │          │  │       ├── ActionText (rich text)  │ │
                    │  └──────────┘  │       ├── Active Storage (files)  │ │
                    │                │       └── Turbo Streams           │ │
                    │                │                                   │ │
                    │                │  Redis (pub/sub, cache)           │ │
                    │                │  Solid Queue (background jobs)    │ │
                    │                └───────────────────────────────────┘ │
                    │                                                      │
                    │  Volume: /disk/sabha/ ──▶ /rails/storage (SQLite)   │
                    └──────────────────────────────────────────────────────┘
```

**Technology choices:**
- **Rails 8.2** with Hotwire (Turbo + Stimulus) for server-rendered HTML with real-time updates
- **SQLite** in production, optimized for single-server deployments
- **AnyCable** for WebSocket scaling (HTTP RPC mode, no gRPC)
- **Tailwind CSS v4** compiled via `@tailwindcss/cli`; **Importmap** for all JavaScript (zero JS bundling)
- **Solid Queue** (SQLite-backed) for background jobs
- **Propshaft** as the asset pipeline

---

## Request Lifecycle

### HTTP Request

```
Browser → Thruster → Puma → Rack middleware → Rails router → Controller → View
                                    │
                                    └── SaaS mode: PathRewriter middleware
                                        extracts /{workspace_id}/ prefix
                                        into SCRIPT_NAME
```

1. **Thruster** terminates TLS, compresses responses, serves cached assets (skipped in Sabha Cloud where Caddy handles this)
2. **Puma** dispatches to Rails
3. **Middleware** (SaaS mode): `PathRewriter` moves the workspace prefix (e.g., `/1000001/`) from PATH_INFO to SCRIPT_NAME, enabling transparent URL generation
4. **Router** matches the request to a controller action
5. **Controller** authenticates via `Current.user` (set in `before_action`), performs the action, renders a view or Turbo Stream

### WebSocket Connection

```
Browser → AnyCable-Go (:8080/cable) → HTTP RPC → Rails (/_anycable)
                                                      │
                                                      └── Connection#connect
                                                          authenticates via
                                                          signed cookie
```

AnyCable-Go handles WebSocket lifecycle; Rails handles authentication and channel logic via HTTP RPC calls. This avoids keeping persistent connections in the Ruby process.

---

## Domain Model

### Core Entities

```
User ──────┐
  │        │ has_many
  │        ▼
  │    Membership ──────▶ Room (STI)
  │        │                 │
  │        │                 ├── Rooms::Open    (public)
  │        │                 ├── Rooms::Closed  (invite-only)
  │        │                 ├── Rooms::Direct  (1:1 / group DMs)
  │        │                 └── Rooms::Thread  (tied to parent message)
  │        │
  │        └── involvement: invisible | nothing | mentions | everything
  │
  ├── has_many: Message (via room)
  │              │
  │              ├── ActionText::RichText (body)
  │              ├── ActiveStorage attachments
  │              ├── Mention (join: message_id + user_id, no PK)
  │              ├── Boost (reactions/reposts)
  │              └── Bookmark
  │
  ├── Session (browser, IP, platform tracking)
  ├── AuthToken (OTP codes for passwordless sign-in)
  ├── Ban (banned users)
  ├── Block (user-to-user blocks)
  └── Push::Subscription (web push endpoints)

Account (singleton) ── workspace-level settings, branding, feature flags
```

### Model Organization

Models primarily use namespace decomposition, with selective service objects where useful:

| Directory | Purpose |
|-----------|---------|
| `app/models/rooms/` | STI subclasses: `Open`, `Closed`, `Direct`, `Thread` |
| `app/models/user/` | `Avatar`, `Bot`, `DicebearAvatar`, `Mentionable`, `Preferences`, `Role`, `Bannable`, `Transferable` |
| `app/models/message/` | `Attachment`, `Broadcasts`, `Mentionee`, `Searchable` |
| `app/models/membership/` | `Connectable` (WebSocket connection state) |
| `app/models/inbox/` | Query objects: `ActivityQuery`, `ThreadsQuery`, `BookmarksQuery`, `MessagesQuery`, `DirectMessagesQuery` |
| `app/models/concerns/` | `Deactivatable` (soft deletion), `Pagination` |

### Soft Deletion

Messages, rooms, memberships, boosts, bookmarks, and accounts use soft deletion via the `Deactivatable` concern (`active` boolean with explicit `active`/`inactive` scopes, not a default scope). Users use a `status` enum (`active`, `deactivated`, `banned`) rather than an `active` boolean.

### System Event Messages

Room lifecycle changes (renames, member additions/removals) are recorded as **system event messages** -- messages with a non-null `event` column (`room_renamed`, `member_joined`, `member_left`). These are created via `Room#post_system_message` which uses `Message.insert!` + `ActionText::RichText.insert!` to bypass all ActiveRecord callbacks (push notifications, search indexing, counter caches, streaks). Only the Turbo Stream append broadcast is emitted. System events are excluded from inbox queries, unread cursor advancement, and search via the `without_events` scope.

### Key Conventions

- **Model-first business logic.** Most behavior lives in models/concerns, with selective service objects (e.g., `SlackImporter`) for isolated workflows.
- **Strictly RESTful controllers.** Only standard CRUD actions (`index`, `show`, `new`, `create`, `edit`, `update`, `destroy`). Custom actions like `leave` or `activate` become `destroy` on a new resource controller (e.g., `MembershipsController#destroy`).
- **Exceptions over return values.** Model methods raise on failure, controllers rescue with redirects.
- **`id: false` tables** (like `mentions`) must use `dependent: :delete_all`, never `:destroy`.

### Room Types in Detail

- **`Rooms::Open`** - Auto-grants membership to all current and future users. New users join all open rooms on creation.
- **`Rooms::Closed`** - Membership must be explicitly granted by an admin or room creator.
- **`Rooms::Direct`** - Identified by an MD5 `members_hash` of sorted user IDs, ensuring one DM room per unique set of participants. Default involvement: `everything`.
- **`Rooms::Thread`** - Tied to a `parent_message`. Inherits permissions from the parent room. Default involvement: `invisible` except for thread creator and parent message author.

### Supporting Models

| Model | Purpose |
|-------|---------|
| `Account` | Singleton workspace settings. `has_json :settings` for feature flags. |
| `Boost` | Message reactions/reshares (soft-deleted) |
| `Bookmark` | Saved messages (soft-deleted) |
| `Mention` | Join table (`message_id` + `user_id`, no PK). Must use `dependent: :delete_all` |
| `Badge` | Custom user badges (name, icon, color) |
| `Ban` | IP address bans tied to users |
| `Block` | User-to-user blocking (prevents DMs) |
| `Sound` | Pure Ruby value object (~50 built-in sounds via `/play name` syntax) |
| `Search` | Persisted search queries with per-user history |
| `Webhook` / `WebhookEvent` | Bot webhook endpoints and delivery records |
| `Push::Subscription` | Web push subscription endpoints (VAPID) |
| `Everyone` | Attachable for `@everyone` mentions (not an AR model) |

### Key Concerns

| Concern | Used By | Purpose |
|---------|---------|---------|
| `Deactivatable` | Account, Room, Message, Membership, Boost, Bookmark | Soft deletion via `active` boolean with scopes |
| `Membership::Connectable` | Membership | WebSocket presence tracking (`connected_at`, 60s TTL). Provides activity status tiers: online (green, connected now), away (yellow, connected within TTL), offline (gray). Powers status indicators on member lists and profiles. |
| `Message::Searchable` | Message | FTS5 full-text search index maintenance |
| `Message::Broadcasts` | Message | Turbo Stream broadcasting on create/update/remove |
| `Message::Mentionee` | Message | Parses ActionText body for @mentions, syncs `mentions` join table |
| `Message::Attachment` | Message | Single file attachment with thumbnail variant |
| `User::Mentionable` | User | ActionText `Attachable` interface for @mention embedding |
| `User::Role` | User | Role enum (`member`, `moderator`, `administrator`, `bot`) with permission methods |
| `User::Bot` | User | Bot authentication via `{id}-{token}` URL key |
| `Pagination` | Message, Bookmark | Cursor-based pagination (`page_before`, `page_after`, `page_around`) |

---

## Authentication

Sabha supports two authentication strategies depending on deployment mode.

### Self-Hosted Mode

```
                    ┌─────────────────────┐
                    │  Sign-In Form       │
                    │  (email + password   │
                    │   or email-only OTP) │
                    └─────────┬───────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
     Password Auth                     Passwordless (OTP)
     (bcrypt hash)                     AuthToken → email
              │                               │
              ▼                               ▼
         Session created               6-digit code verified
         (session_token cookie)        Session created
              │
              ▼
         Current.user set via
         before_action callback
```

- **Session model** tracks browser, IP, platform for multi-device support
- Auth method is configured globally via `ENV["AUTH_METHOD"]` (read through `Account#auth_method_value`)
- Email verification required for new users (`verified_at` timestamp)
- Cloudflare Turnstile bot protection on sign-in forms (production)

### SaaS Mode

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

- `GlobalIdentity` is the cross-workspace user record (email + name, no password). The `name` field syncs bidirectionally with workspace `User` records -- set during registration and updated when a user changes their name in any workspace.
- `GlobalSession` persists across workspaces via `global_session_token` cookie
- `WorkspaceMembership` links a `GlobalIdentity` to a specific workspace tenant
- SaaS mode enforces OTP-only authentication (no password auth)

### Current Context

```ruby
# Self-hosted:
Current.user       # Authenticated user
Current.session    # Session record
Current.account    # Workspace settings (singleton)
Current.request    # HTTP request

# SaaS (additional):
Current.global_session        # Cross-workspace session
Current.global_identity       # Identity (via global_session)
Current.workspace_membership  # Link to current workspace
Current.workspace             # Current Workspace record
# Current.user derived from workspace_membership.user
```

---

## Real-Time Layer

### Channel Architecture

```
                    AnyCable-Go
                        │
                        ▼
              ApplicationCable::Connection
              (authenticates via signed cookie)
                        │
          ┌─────────────┼─────────────────────┐
          ▼             ▼                     ▼
    RoomChannel    PresenceChannel     RoomListChannel
    (messages)     (online users)      (sidebar updates)
          │
    ┌─────┼──────────────┬──────────────────┐
    ▼     ▼              ▼                  ▼
 Typing  Heartbeat   UserUnread        InboxActivity
 Notifs  Channel     RoomsChannel      Channel
                                            │
                                     ┌──────┼──────┐
                                     ▼      ▼      ▼
                                  Threads Bookmarks DMs
                                  Channel Channel  Channel
```

| Channel | Purpose |
|---------|---------|
| `RoomChannel` | Message broadcasts to room subscribers |
| `PresenceChannel` | Online/offline user tracking |
| `RoomListChannel` | Sidebar room list updates (new rooms, reordering) |
| `UserUnreadRoomsChannel` | Per-user unread room badges |
| `TypingNotificationsChannel` | "User is typing..." indicators |
| `HeartbeatChannel` | Connection keep-alive |
| `ReadRoomsChannel` | Marks rooms as read |
| `UserInvolvementsChannel` | Notification preference changes |
| `InboxActivityChannel` | Real-time inbox: @mentions |
| `InboxThreadsChannel` | Real-time inbox: thread replies |
| `InboxDirectMessagesChannel` | Real-time inbox: DMs |
| `InboxBookmarksChannel` | Real-time inbox: bookmarks |
| `UnreadNotificationsChannel` | Unread notification count |

### Turbo Streams

Server-side broadcasts use Turbo Streams for DOM updates without custom JavaScript:

```ruby
# Model callback broadcasts
broadcast_append_to room, :messages, partial: "messages/message"
broadcast_replace_to room, :unread_count, target: "unread-#{room.id}"
```

Turbo Streams handle: appending new messages, replacing unread counts, updating room lists, removing deleted content, and refreshing user presence indicators.

Turbo Stream broadcasts are emitted from models, jobs, and selected controller actions (for scoped UI updates like bookmarks/involvements). Typing notifications are handled by `TypingNotificationsChannel`, and use `whisper: true` when AnyCable is enabled.

---

## Frontend Architecture

### Build Pipeline

```
                 ┌──────────────┐
                 │ Tailwind CLI │──── @tailwindcss/cli ──▶ app/assets/builds/tailwind.css
                 │ (CSS only)   │
                 └──────────────┘

                 ┌──────────────┐
                 │  Importmap   │──── ES modules ──▶ browser (no bundling)
                 │ (all JS)     │
                 └──────────────┘

                 ┌──────────────┐
                 │  Propshaft   │──── static assets ──▶ fingerprinted files
                 │ (pipeline)   │
                 └──────────────┘
```

Tailwind CSS v4 is compiled via `@tailwindcss/cli` (pnpm). All JavaScript loads as native ES modules via Importmap -- no bundler, no transpilation.

### Directory Layout

```
app/frontend/
├── entrypoints/
│   └── application.css       # Tailwind v4 source (input for @tailwindcss/cli)
├── application.js            # Main JS entry (Importmap): Turbo, Trix, Stimulus
├── initializers/             # Setup modules (autocomplete, current user, rich text)
├── controllers/              # 50+ Stimulus controllers
│   ├── messages_controller.js        # Core message area
│   ├── composer_controller.js        # Rich text composer
│   ├── presence_controller.js        # Online/offline tracking
│   ├── typing_notifications_controller.js
│   ├── rooms_list_controller.js      # Sidebar room list
│   ├── inbox_controller.js           # Inbox tabs
│   ├── notifications_controller.js   # Web push subscription
│   └── ...
├── channels/                 # ActionCable JS subscriptions
├── helpers/                  # DOM, navigator, string, timing, Turbo utilities
├── lib/
│   ├── autocomplete/         # @mention autocomplete (Web Components)
│   └── rich_text/unfurl/     # URL unfurling for link previews
└── models/                   # Client-side: scroll, pagination, typing, uploads
```

### Styling

Tailwind CSS v4 with a custom OKLCH color system supporting light and dark modes. Semantic color tokens (`--color-bg`, `--color-text`, `--color-link`) abstract the palette for theme flexibility. Plugins: `@tailwindcss/typography`, `@tailwindcss/forms`.

---

## Background Jobs

**Solid Queue** (SQLite-backed) for background job processing.

- **Dev/test:** Runs inside Puma via `plugin :solid_queue` (no separate process needed)
- **Production:** Runs as separate workers via Procfile (`rake solid_queue:start`)
- **Override:** Set `SOLID_QUEUE_IN_PUMA=true` in production to run inside Puma

```
Procfile (production):
  web:     bin/start-app          # Puma (via Thruster)
  redis:   redis-server           # ActionCable pub/sub + cache
  workers: rake solid_queue:start # Background job processing
```

Configuration (`config/queue.yml`):
- 1 dispatcher (polling every 1s, batch size 500)
- Workers: 3 threads, process count from `JOB_CONCURRENCY` env (default: 1)

### Job Classes

| Job | Purpose |
|-----|---------|
| `Room::PushMessageJob` | Web push notifications for new messages (fans out via `Room::MessagePusher`) |
| `Bot::WebhookJob` | Delivers webhook payloads to bot endpoints, handles text/attachment replies |
| `BroadcastInboxDirectMessagesJob` | Real-time DM inbox updates |
| `BroadcastInboxThreadsJob` | Real-time thread inbox updates |
| `RemoveBannedContentJob` | Cleans up content from banned users |
| `RoomUpdateBroadcastJob` | Broadcasts room list updates |

### Recurring Jobs

- `SolidQueue::Job.clear_finished_in_batches` - Hourly cleanup of completed job records

### Web Push

A dedicated thread pool (`WebPush::Pool`) handles push notification delivery:
- 50 delivery threads, 1 invalidation thread
- 150 persistent HTTP connections (via `net-http-persistent`)
- In SaaS mode, captures tenant context before dispatching to the thread pool

---

## SaaS / Multi-Tenant

The multi-tenant layer is a Rails engine in `saas/`, enabled via `Sabha.saas?` (set by `SAAS=true` env var or `tmp/saas.txt` marker file).

### Architecture

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

- **Untenanted database** (PostgreSQL): `GlobalIdentity`, `Workspace`, `WorkspaceMembership`, `GlobalSession`, `AuthCode` -- these models inherit from `UntenantedRecord`
- **Tenanted databases** (SQLite, one per workspace): All application models (`User`, `Room`, `Message`, etc.) -- stored at `storage/workspaces/{env}/{tenant_id}/db/main.sqlite3`
- Tenant isolation via `activerecord-tenanted` gem

### Request Flow (SaaS)

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

### SaaS Engine Structure

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

## Database

### Self-Hosted: SQLite

All data lives in SQLite databases on a single volume:

```
storage/
├── db/
│   ├── production.sqlite3          # Main database
│   ├── production_queue.sqlite3    # Solid Queue jobs
└── files/
    └── ...                         # Active Storage files
```

**Configuration** (`config/database.sqlite.yml`):
- `default_transaction_mode: immediate` to reduce write-contention surprises
- connection timeout/retry tuning (`timeout`, `retries`)
- SQLite runtime pragmas (WAL/busy timeout/synchronous) are handled by the Rails SQLite adapter

### Full-Text Search (FTS5)

Message search uses SQLite's FTS5 extension:

```
message_search_index (virtual table)
  ├── content synced from messages table
  └── queried via Message::Searchable concern
```

Schema format is Ruby (`db/schema.rb`), using `create_virtual_table` for FTS5.

### SaaS: PostgreSQL + SQLite

- **PostgreSQL** (`sabha_untenanted_{env}`): Platform-level records (identity, workspace, sessions)
- **SQLite** (per workspace): All application data, isolated per tenant
- Untenanted migrations: `saas/db/untenanted_migrate/`
- Tenanted migrations: standard `db/migrate/` (applied per-workspace)

---

## Deployment

All deployment modes share the same container architecture: **3 containers** (web + AnyCable-Go + reverse proxy) with Redis and Solid Queue workers running inside the web container. AnyCable-Go always runs as a **separate container**, communicating with Rails via HTTP RPC at `/_anycable`.

### SaaS (Kamal + kamal-proxy)

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
- `SKIP_THRUSTER=true` -- Puma runs directly, no Thruster wrapper
- Deployed via `kamal deploy -d multitenant` (config: `config/deploy.multitenant.yml`)

### Managed Hosting (Docker Compose + Caddy)

```
┌──────────────────────────────────────────────────┐
│  DigitalOcean Droplet (per customer)              │
│                                                   │
│  Caddy (:443, :80)  ─── auto HTTPS + HTTP/3       │
│      │ /cable     │ /*                             │
│      ▼            ▼                                │
│  AnyCable-Go   Web Container                       │
│  (:8080)         Puma :3000                        │
│                  Redis (in-container)               │
│                  Solid Queue workers                │
│                                                    │
│  Docker volume: campfire_data → /rails/storage     │
│  (single SQLite database)                          │
└──────────────────────────────────────────────────┘
```

- **Caddy** handles automatic HTTPS (Let's Encrypt), HTTP/3, compression, and security headers
- **Docker Compose** orchestrates 3 containers: `web`, `campfire-anycable`, `caddy`
- Single-tenant mode (no SAAS env), `AUTH_METHOD=password`
- Health check at `/up` with auto-restart

### Self-Hosted (Kamal + Thruster)

For users deploying their own instance via Kamal:
- **Thruster** wraps Puma for HTTP/2, TLS, compression, and static asset caching (when `SKIP_THRUSTER` is not set)
- **AnyCable-Go** runs as a Kamal accessory with path prefix `/cable`
- Same 3-container pattern: kamal-proxy + web + AnyCable-Go

### Startup Sequence

```
bin/boot
    │
    ├── Pre-boot (production only):
    │   ├── mkdir -p storage/logs
    │   ├── rails db:prepare
    │   └── rails db:seed           # SaaS mode only
    │
    └── ProcessMonitor (reads Procfile):
        ├── bin/start-app           # Puma (via Thruster or direct)
        ├── redis-server            # Redis for pub/sub + cache
        └── solid_queue:start       # Background workers (skipped if SOLID_QUEUE_IN_PUMA=true)
```

### Docker Image

Multi-stage build:
1. **Build stage**: Ruby + Node.js + pnpm → install gems, compile Tailwind (`@tailwindcss/cli`), precompile assets (Propshaft)
2. **Runtime stage**: Minimal image with `libsqlite3`, `libvips`, `jemalloc`, `ffmpeg`, `redis-server` -- runs as non-root `sabha` user with YJIT enabled

---

## Key Dependencies

| Gem | Purpose |
|-----|---------|
| `rails` (edge) | Framework |
| `sqlite3` | Primary database |
| `puma` | Web server |
| `thruster` | HTTP/2 + TLS proxy |
| `anycable-rails-core` | WebSocket scaling (HTTP RPC) |
| `redis` | Pub/sub + cache store |
| `solid_queue` | Background jobs (SQLite-backed) |
| `turbo-rails` | Turbo Drive, Frames, Streams |
| `stimulus-rails` | Stimulus controllers |
| `importmap-rails` | ES module loading (no bundler) |
| `@tailwindcss/cli` (npm) | Tailwind CSS v4 compilation |
| `propshaft` | Asset pipeline |
| `bcrypt` | Password hashing |
| `resend` | Transactional email |
| `web-push` | VAPID web push notifications |
| `image_processing` | Active Storage image variants |
| `geared_pagination` | Cursor-based pagination |
| `kredis` | Higher-level Redis data structures |
| `sentry-ruby` | Error tracking (production) |
| `rails_cloudflare_turnstile` | Bot protection |
| `activerecord-tenanted` | Multi-tenant database isolation (SaaS) |

---

## Routes Structure

Routes are organized RESTfully around resources:

| Path | Controller | Purpose |
|------|-----------|---------|
| `/session` | `SessionsController` | Sign in/out |
| `/auth_tokens` | `AuthTokensController` | OTP code generation |
| `/account` | `AccountsController` | Workspace settings (admin) |
| `/account/users` | `Accounts::UsersController` | User management |
| `/account/bots` | `Accounts::BotsController` | Bot management |
| `/rooms` | `RoomsController` | Room CRUD |
| `/rooms/:id/messages` | `MessagesController` | Messages within a room |
| `/rooms/opens` | `Rooms::OpensController` | Public room creation |
| `/rooms/closeds` | `Rooms::ClosedsController` | Private room creation |
| `/rooms/directs` | `Rooms::DirectsController` | DM creation |
| `/rooms/threads` | `Rooms::ThreadsController` | Thread management |
| `/messages/:id/boosts` | `Messages::BoostsController` | Reactions |
| `/messages/:id/bookmarks` | `Messages::BookmarksController` | Bookmarks |
| `/inbox` | `InboxesController` | Inbox (activity, threads, DMs, bookmarks) |
| `/searches` | `SearchesController` | Full-text search |
| `/users/:id` | `UsersController` | User profiles |
| `/join/:code` | `UsersController` | Invite link signup |

SaaS mode prepends `/{workspace_id}/` to all workspace-scoped routes (handled transparently by the PathRewriter middleware).

---

## Architectural Decisions

1. **SQLite as the production database.** Tuned with `default_transaction_mode: immediate` plus adapter/runtime SQLite optimizations. FTS5 provides full-text search without an external search service via the `message_search_index` virtual table.

2. **Importmap for JS, Tailwind CLI for CSS.** Avoids bundler complexity. Browsers load Stimulus controllers directly as ES modules. Tailwind CSS v4 is compiled via `@tailwindcss/cli` -- no Vite, no bundler.

3. **AnyCable-Go for WebSockets.** Uses HTTP RPC mode (no gRPC dependency). Scales WebSocket connections outside the Ruby process while keeping authentication and channel logic in Rails.

4. **Soft deletion is first-class.** Account/content models use an `active` boolean with scoped queries, while `User` uses a `status` enum (`active`/`deactivated`/`banned`). Hard-delete paths use `unscoped` cleanup where needed.

5. **Namespace decomposition first; services where they help.** User concerns live in `User::Role`, `User::Bot`, etc., while standalone workflows (e.g., imports) can live in `app/services/`.

6. **Broadcasts are close to state changes.** Most real-time updates are model/job-driven, with targeted controller broadcasts for user-scoped UI changes.

7. **Lazy user creation in SaaS mode.** A `User` record in a workspace database is only created when a `GlobalIdentity` member first visits that workspace, avoiding pre-provisioning across all workspaces.

8. **Tenant context propagated automatically.** The `activerecord-tenanted` gem serializes `current_tenant` with Solid Queue job payloads and wraps ActionCable channel commands with the correct tenant, eliminating manual tenant management.

9. **3-container deployment.** The web container runs Puma, Redis, and Solid Queue workers together. AnyCable-Go runs as a separate container for WebSocket scaling. A reverse proxy (kamal-proxy, Caddy, or Thruster) handles TLS and routes `/cable` traffic to AnyCable-Go. This keeps operations simple while separating WebSocket connections from the Ruby process.
