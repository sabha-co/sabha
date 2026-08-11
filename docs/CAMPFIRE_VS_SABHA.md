# Once Campfire vs Sabha

Sabha is a fork of [Once Campfire](https://once.com/campfire) by 37signals. This document covers what Sabha adds, changes, and removes.

---

## New Features

### Community Management

| Feature | Description |
|---------|-------------|
| **User management** | Admins can manage users from the UI. Promote/demote users between member, moderator, and administrator roles. |
| **User banning** | Admins ban users — terminates sessions, soft-deletes messages, blocks IP addresses. Unbanning restores the account. |
| **User blocking** | Members can block other users from DMing or @-mentioning them. Symmetric — either party blocking stops the contact. |
| **User badges** | Custom badges (name + color) to highlight member roles or titles. |
| **User search** | Search members by name or email in the admin panel. |
| **User reactivation** | Admins can reactivate deactivated users from the UI. |

### Inbox System

Split inbox with dedicated views and real-time updates:

- **Activity** — @mentions and @everyone
- **Threads** — replies to threads you're participating in
- **DMs** — direct message conversations
- **Bookmarks** — saved messages

### Authentication

Flexible authentication, configurable via `AUTH_METHOD`:

| Method | Flow |
|---|---|
| **Password** (default) | Email + password with bcrypt |
| **OTP** | Email → 6-digit code → verified |

Also: email verification for new users, password reset, QR code session transfer between devices.

### DiceBear Avatars

Auto-generated avatars for users without profile photos. Users can shuffle to get a new random design. Configurable style.

### Personal Invite Links

Members can generate personal invite links from their profile (if enabled by admin). Links auto-expire after 7 days. The signup page shows the inviter's name and community stats.

### Bot API

Sabha extends Campfire's write-only bot system into an agent-ready REST + WebSocket API under `/api/bots/`. See [BOT_INTEGRATION.md](features/BOT_INTEGRATION.md) for the full surface.

| Capability | Campfire | Sabha |
|---|---|---|
| Post messages | Yes | Yes |
| Mention webhooks | Yes (7s timeout) | Yes (300s timeout, HMAC-signed) |
| Self-registration | No | `POST /join/{code}` returns `bot_key` + `webhook_secret` |
| API discovery | No | `GET /skill` (plain-text, LLM-readable) |
| Read messages | No | `GET /api/bots/rooms/{room_id}/messages` (cursor-paginated) |
| Edit / delete own messages | No | `PATCH` / `DELETE /api/bots/messages/{id}` |
| Reactions | No | `POST` / `DELETE /api/bots/messages/{id}/boosts` |
| Room management | No | Create, archive, join, leave, manage members |
| Create DMs | No | `POST /api/bots/direct_messages` |
| Real-time WebSocket | No | `wss://.../cable?bot_key=…` subscribing to `BotEventsChannel` |
| Structured errors | No | JSON `{ error, code }` envelope |
| SSRF protection | No | Webhook URL validation, endpoint allowlist |

The 300-second webhook timeout plus real-time WebSocket delivery make the bot system practical for LLM-powered agents that connect outbound and don't need a public webhook URL.

### Slack Import

Full Slack workspace migration including users, channels, messages, threads, and reactions. Imported users are created as placeholder accounts (no email, no password); admins can later attach a real email and password to a placeholder via the console or admin UI. Idempotent — safe to re-run. Experimental and may not work for all workspaces.

### Themes

Users select Light, Dark, or Auto from their profile. Applied before page render to avoid flash.

### Presence Tracking

Three status tiers: online, away, offline. 60-second TTL.

### Branding Customization

Full white-label — app name, support email, PWA colors, icons. See [BRANDING.md](./BRANDING.md).

### Welcome Messages

New members receive an automatic welcome message when they join, with the community join link shown to admins. Configurable per account.

### Email Providers

Supports multiple email providers via the standard ActionMailer delivery interface — Resend (default for self-hosted) and AWS SES (default for SaaS). Sender domain configured per deployment.

### Email Notifications

Bundled missed-notification email and a separate weekly activity digest. Bundles coalesce mentions and DMs into one email per hour or per day (user-selectable) — no spam from chatty rooms. Weekly digest is admin-enabled with per-member opt-out. Both email surfaces default off; opt in via the notification preferences page. See [NOTIFICATIONS.md](features/NOTIFICATIONS.md).

### Notification Preferences

Dedicated profile area for notification settings: global mode (everything / mentions+DMs / nothing), email bundle frequency, weekly digest opt-in, push toggle. Per-room overrides layer on top of the global mode.

### Single Sign-On

Self-hosted Sabhas can hand off sign-in to an external identity provider (HMAC-signed payload over `sso/handshake` and `sso/callback`). Sabha SaaS can act as that provider for self-hosted installs.

### Other

- **User streaks** — consecutive days of posting with tiered icons
- **System event messages** — room renames, member joins/leaves recorded as special messages

---

## Architectural Changes

### AnyCable

[AnyCable](https://docs.anycable.io/) is a high-performance WebSocket server written in Go that replaces Rails' built-in ActionCable, allowing Sabha to handle significantly more concurrent connections with less memory. Required, in HTTP RPC mode — it carries all real-time delivery. Benchmarks show 10x faster WebSocket connections and 2x message throughput vs ActionCable.

### Solid Queue

[Solid Queue](https://github.com/solidqueue/solid_queue) is the database-backed background job system now standard in Rails. Sabha runs it on SQLite, so the **job queue** no longer needs Redis (Redis is still used elsewhere — cache store, ActionCable / AnyCable pubsub, Kredis):

- **SQLite-backed jobs** — job rows live in the same database family as the app
- **Runs inside Puma in development** — no separate worker process for local development
- **Separate workers in production** — dedicated processes for throughput and isolation
- **Future-proof** — Rails default going forward; replaces older Resque-style queues

### Multi-Tenant SaaS Mode

Optional Rails engine in `saas/` for database-per-workspace isolation:

- PostgreSQL for shared data (identities, workspaces, sessions)
- SQLite per workspace for all app data
- Path-based routing (`/1000001/rooms/general`)
- OTP-only auth via GlobalIdentity
- Tenant context auto-propagated to jobs and channels

Also includes:
- **Platform superadmin area** — admin dashboard for managing all workspaces
- **Event-sourced storage tracking** — per-workspace storage usage monitoring
- **Workspace provisioning screen** — guided setup flow with invite step after creation

See [multi-tenant/](./multi-tenant/) docs. The `saas/` directory is under the [Sabha SaaS License](../saas/LICENSE), not MIT.

### Soft Deletion

Comprehensive soft deletion for messages, rooms, and memberships. Users have a status (`active` / `deactivated` / `banned`). Room deactivation cascades to threads, memberships, and messages. Deactivating a user also cascades to their DM rooms — both participants lose visibility — while leaving Open and Closed memberships untouched. See [SOFT_DELETION_AND_USER_STATES.md](features/SOFT_DELETION_AND_USER_STATES.md).

### Deployment

Three-container architecture: web (Puma + Redis + Solid Queue workers), AnyCable-Go, reverse proxy (kamal-proxy or Thruster). Deployed via Kamal or Docker Compose. Redis powers the cache store and ActionCable / AnyCable pubsub; job storage is SQLite via Solid Queue.

---

## Features Inherited from Small Bets

Sabha includes features, originally added by [Antiwork's Small Bets fork](https://github.com/antiwork/smallbets) of Campfire. But refined and improved upon.

- Mentions tab and @mention notifications
- Bookmarks (save messages)
- Threads (message-tied discussions)
- Unread message indicators ("New since last visit" line)
- Mark as unread
- User blocking (DM prevention)
- One-click reboost
- Soft deletion for all content models
- Empty DM hiding in sidebar
- Sidebar scroll preservation

### Removed from Small Bets Changes

- **Video library** — removed Inertia.js/React infrastructure; Sabha is server-rendered only
- **Expert role** — removed expert directory and "answered" message functionality
- **Stats dashboard** — replaced with simpler user streaks
- **Room URL slugs** — users navigate via sidebar, not URL slugs
- **Room merge** — data integrity concerns
- **Email digest notifications** — removed
- **Marketing pages** — unauthenticated users redirect to sign-in
