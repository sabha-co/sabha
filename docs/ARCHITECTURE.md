# Sabha Architecture

Sabha is a real-time chat application built with Ruby on Rails, Hotwire, and SQLite.

> For multi-tenant SaaS architecture, see [multi-tenant/ARCHITECTURE.md](./multi-tenant/ARCHITECTURE.md).

[Visual architecture diagrams (Excalidraw)](./multi-tenant/once-campfire-architecture.excalidraw)

---

## Table of Contents

- [System Overview](#system-overview)
- [Request Lifecycle](#request-lifecycle)
- [Domain Model](#domain-model)
- [Authentication](#authentication)
- [Real-Time Layer](#real-time-layer)
- [Frontend Architecture](#frontend-architecture)
- [Background Jobs](#background-jobs)
- [Database](#database)
- [Deployment](#deployment)
- [Key Dependencies](#key-dependencies)

---

## System Overview

```
                    ┌──────────────────────────────────────────────────────┐
                    │  Server (single host)                                │
                    │                                                      │
  Browser ─HTTPS──▶ │  Kamal Proxy (:443)                                │
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
- **AnyCable** for WebSocket scaling (HTTP RPC mode)
- **Tailwind CSS v4** compiled via `@tailwindcss/cli`; **Importmap** for all JavaScript (zero JS bundling)
- **Solid Queue** (SQLite-backed) for background jobs
- **Propshaft** as the asset pipeline

---

## Request Lifecycle

### HTTP Request

```
Browser → kamal-proxy → Thruster → Puma → Rack middleware → Rails router → Controller → View
```

1. **kamal-proxy** terminates TLS, routes `/cable` to AnyCable-Go, everything else to the web container
2. **Thruster** compresses responses, serves cached assets
3. **Puma** dispatches to Rails
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
  │              ├── Mention (parsed from ActionText body HTML, persisted for history)
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
| `app/models/user/` | `Avatar`, `Bannable`, `Blockable`, `Bot`, `DicebearAvatar`, `EmailChangeable`, `Mentionable`, `Notifiable`, `PasswordAuthable`, `Role`, `SaasBridged`, `Streakable`, `Transferable`, `Verifiable` |
| `app/models/message/` | `Attachment`, `Broadcasts`, `Mentionee`, `Searchable`, `Streakable`, `Threadable`, `Unreadable` |
| `app/models/membership/` | `Cacheable`, `Connectable`, `Involvable`, `Notifiable`, `Starrable` |
| `app/models/inbox/` | Query objects: `ActivityQuery`, `ThreadsQuery`, `BookmarksQuery`, `MessagesQuery`, `DirectMessagesQuery` |
| `app/models/concerns/` | `Deactivatable` (soft-delete via `active` boolean), `Pagination` |

### Key Conventions

- **Model-first business logic.** Most behavior lives in models/concerns. Isolated workflows that need their own namespace (e.g., `Slack::Importer` and friends under `lib/slack/`) sit next to their collaborators rather than in an `app/services/` bucket.
- **Strictly RESTful controllers.** Only standard CRUD actions (`index`, `show`, `new`, `create`, `edit`, `update`, `destroy`). Custom actions like `leave` or `activate` become `destroy` on a new resource controller (e.g., `MembershipsController#destroy`).
- **Exceptions over return values.** Model methods raise on failure, controllers rescue with redirects.
- **`id: false` tables** (like `mentions`) must use `dependent: :delete_all`, never `:destroy`.
- **Soft deletion via `Deactivatable` concern.** Three models (`Message`, `Room`, `Membership`) use an `active` boolean with two named scopes (`active`, `inactive`) — there is no `default_scope`. `User` uses a `status` enum (`active`/`deactivated`/`banned`) instead. Hard-delete cleanup is enforced explicitly in `destroy_all_associated_records` for FK ordering, not for soft-delete bypass.
- **System event messages bypass callbacks.** Room lifecycle changes (renames, joins, leaves) are recorded via `Message.insert!` to skip push notifications, search indexing, and counter caches. Excluded from inbox queries and search via `without_events` scope.

### Room Types in Detail

- **`Rooms::Open`** - Auto-grants membership to all current and future users. New users join all open rooms on creation.
- **`Rooms::Closed`** - Membership must be explicitly granted by an admin or room creator.
- **`Rooms::Direct`** - Identified by an MD5 `members_hash` of sorted user IDs, ensuring one DM room per unique set of participants. Default involvement: `everything`.
- **`Rooms::Thread`** - Tied to a `parent_message`. Inherits permissions from the parent room. Default involvement: `invisible` except for thread creator and parent message author.

### All Models

| Model | Purpose |
|-------|---------|
| `User` | User record with role enum (`member`, `moderator`, `administrator`, `bot`) |
| `Room` | STI base class for `Open`, `Closed`, `Direct`, `Thread` |
| `Membership` | User ↔ Room link with involvement level |
| `Message` | Chat message with ActionText body and attachments |
| `Account` | Singleton workspace settings. `has_json :settings` for feature flags |
| `Boost` | Message reactions/reshares |
| `Bookmark` | Saved messages |
| `Mention` | Join table (`message_id` + `user_id`, no PK). Must use `dependent: :delete_all` |
| `Badge` | Custom user badges (name, icon, color) |
| `Ban` | IP address bans tied to users |
| `Block` | User-to-user blocking (prevents DMs) |
| `Session` | Browser sessions (IP, platform tracking) |
| `AuthToken` | OTP codes for passwordless sign-in |
| `Search` | Persisted search queries with per-user history |
| `Sound` | Pure Ruby value object (~50 built-in sounds via `/play name` syntax) |
| `Webhook` / `WebhookEvent` | Bot webhook endpoints and delivery records |
| `Push::Subscription` | Web push subscription endpoints (VAPID) |
| `Everyone` | Attachable for `@everyone` mentions (not an AR model) |

---

## Authentication

Configurable via `AUTH_METHOD` environment variable.

```
                 ┌────────────────────────┐
                 │ Auth entry point       │
                 │ (/session/new or SSO)  │
                 └───────────┬────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
 Password Auth        Passwordless (OTP)       SSO
 (bcrypt hash)        AuthToken → email        DiscourseConnect
        │                    │                    │
        ▼                    ▼                    ▼
 Session created      6-digit code verified    Signed callback verified
 (session_token)      Session created          User resolved/provisioned
        │                    │                    │
        └────────────────────┴────────────────────┘
                             ▼
                    Current.user set via
                    before_action callback
```

- **Session model** tracks browser, IP, platform for multi-device support
- Auth method is configured globally via `ENV["AUTH_METHOD"]` (read through `Account#auth_method` and predicate helpers)
- SSO mode stores parent-app identity mappings in `SingleSignOnRecord`
- Email verification required for new users (`verified_at` timestamp)
- Cloudflare Turnstile bot protection on sign-in forms (production)

### Current Context

```ruby
Current.user       # Authenticated user
Current.session    # Session record
Current.account    # Workspace settings (singleton)
Current.request    # HTTP request
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
app/javascript/
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

---

## Deployment

Deployed via [Kamal](https://kamal-deploy.org/) with 3 containers:

- **kamal-proxy** — TLS termination (Let's Encrypt), routes `/cable` to AnyCable-Go, everything else to the web container
- **Web container** — Thruster (compression, asset caching) → Puma, Redis, and Solid Queue workers
- **AnyCable-Go** — WebSocket server, communicates with Rails via HTTP RPC at `/_anycable`

### Startup Sequence

```
bin/boot
    │
    ├── Pre-boot (production only):
    │   ├── mkdir -p storage/logs
    │   └── rails db:prepare
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

---

## Architectural Decisions

1. **SQLite as the production database.** Tuned with `default_transaction_mode: immediate` plus adapter/runtime SQLite optimizations. FTS5 provides full-text search without an external search service via the `message_search_index` virtual table.

2. **Importmap for JS, Tailwind CLI for CSS.** Avoids bundler complexity. Browsers load Stimulus controllers directly as ES modules. Tailwind CSS v4 is compiled via `@tailwindcss/cli` -- no Vite, no bundler.

3. **AnyCable-Go for WebSockets.** Uses HTTP RPC mode (no gRPC dependency). Scales WebSocket connections outside the Ruby process while keeping authentication and channel logic in Rails.

4. **Soft deletion is first-class.** `Message`, `Room`, and `Membership` use an `active` boolean with named scopes (`active`/`inactive`); `User` uses a `status` enum (`active`/`deactivated`/`banned`). Hard-delete cascade order is enforced explicitly in `destroy_all_associated_records` for FK satisfaction (notifications before messages, bundle items before bundles), not for soft-delete bypass — see [`docs/plans/deactivatable-refactor.html`](./plans/deactivatable-refactor.html) for the audit that established this.

5. **Namespace decomposition first; no service layer.** User concerns live in `User::Role`, `User::Bot`, etc. Multi-step workflows live next to their collaborators (e.g., `Slack::Importer` under `lib/slack/`) rather than in a dedicated `app/services/` directory — which doesn't exist in Sabha.

6. **Broadcasts are close to state changes.** Most real-time updates are model/job-driven, with targeted controller broadcasts for user-scoped UI changes.

7. **3-container deployment.** The web container runs Puma, Redis, and Solid Queue workers together. AnyCable-Go runs as a separate container for WebSocket scaling. A reverse proxy (kamal-proxy or Thruster) handles TLS and routes `/cable` traffic to AnyCable-Go. This keeps operations simple while separating WebSocket connections from the Ruby process.
