# Once Campfire vs Sabha

Sabha is a fork of [Once Campfire](https://once.com/campfire) by 37signals. This document covers what Sabha adds, changes, and removes.

---

## New Features

### Community Management

| Feature | Description |
|---------|-------------|
| **User management** | Admins can manage users from the UI. Promote/demote users between member, moderator, and administrator roles. |
| **User banning** | Admins ban users — terminates sessions, soft-deletes messages, blocks IP addresses. Unbanning restores the account. |
| **User blocking** | Members block other users from sending DMs. Admins can see who's being blocked. |
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

Sabha extends Campfire's write-only bot system into an openclaw like autonomous-agent-ready API:

| Capability | Campfire | Sabha |
|---|---|---|
| Post messages | Yes | Yes |
| Mention webhooks | Yes (7s timeout) | Yes (300s timeout) |
| Self-registration | No | `POST /join/{code}` with JSON |
| API discovery | No | `GET /skill` (LLM-readable) |
| List rooms | No | `GET /rooms/{bot_key}` |
| Read messages | No | `GET /rooms/{room_id}/{bot_key}/messages` |
| Create DMs | No | `POST /rooms/{bot_key}/directs` |
| Bot self-update | No | `PATCH /bots/{bot_key}` |
| Everything webhook | No | Receives all events |
| Structured errors | No | JSON `error` + `code` fields |
| SSRF protection | No | Webhook URL validation |

The 300-second webhook timeout is key — it makes the bot system practical for LLM-powered agents.

### Slack Import

Full Slack workspace migration including users, channels, messages, threads, and reactions. Placeholder accounts for absent users can be claimed later. Idempotent — safe to re-run.

### Themes

Users select Light, Dark, or Auto from their profile. Applied before page render to avoid flash.

### Presence Tracking

Three status tiers: online, away, offline. 60-second TTL.

### Branding Customization

Full white-label — app name, support email, PWA colors, icons. Custom CSS via admin panel. See [BRANDING.md](./BRANDING.md).

### Welcome Messages

New members receive an automatic welcome message when they join, with the community join link shown to admins. Configurable per account.

### Email Providers

Supports multiple email providers. Resend (default) and AWS SES for SaaS. SES includes HTML email templates with open tracking.

### Other

- **User streaks** — consecutive days of posting with tiered icons
- **System event messages** — room renames, member joins/leaves recorded as special messages
- **Sound effects** — `/play name` syntax with ~50 built-in sounds
- **Bookmark indicators** — icon on bookmarked messages
- **@everyone mentions** — broadcast mentions to all room members
- **Push notifications and PWA** — VAPID web push with connection-aware delivery

---

## Architectural Changes

### AnyCable

[AnyCable](https://docs.anycable.io/) is a high-performance WebSocket server written in Go that replaces Rails' built-in ActionCable, allowing Sabha to handle significantly more concurrent connections with less memory. Enabled by default (HTTP RPC mode). Benchmarks show 10x faster WebSocket connections and 2x message throughput vs ActionCable. This is optional and can be disabled by setting `ENABLE_ANYCABLE=false`.

### Solid Queue

[Solid Queue](https://github.com/solidqueue/solid_queue) is a modern, Redis-backed job processing library for Ruby on Rails. It provides a simple, reliable way to run background jobs, with features like:

- **SQLite-backed** — uses SQLite for job storage, eliminating the need for Redis
- **Runs inside Puma** — development jobs run inside the Puma process, no separate workers needed
- **Production workers** — separate workers for production environments
- **Future-proof** — ensures future support as resque gem is old and solidqueue is rails default now.

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

Comprehensive soft deletion for messages, rooms, and memberships. Users have a status (active/deactivated/banned). Room deactivation cascades to threads, memberships, and messages. DM memberships are preserved so other participants keep their history.

### Deployment

Three-container architecture: web (Puma + Redis + Solid Queue), AnyCable-Go, reverse proxy (kamal-proxy or Thruster). Deployed via Kamal or Docker Compose.

---

## Inherited from Small Bets

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
