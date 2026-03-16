# Once Campfire vs Sabha

Sabha is a fork of [Once Campfire](https://once.com/campfire) by 37signals. This document covers what Sabha adds, changes, and removes.

---

## New Features

### Community Management

| Feature | Description |
|---------|-------------|
| **User banning** | Admins ban users — terminates sessions, soft-deletes messages, blocks IP addresses. Unbanning restores the account. |
| **User blocking** | Members block other users from sending DMs. Admins can see who's being blocked. |
| **Role management** | Promote/demote users between member, moderator, and administrator roles. |
| **User badges** | Custom badges (name + color) to highlight member roles or titles. |
| **User search** | Search members by name or email in the admin panel. |
| **User reactivation** | Admins can reactivate deactivated users from the UI. |

### Personal Invite Links

Members can generate personal invite links from their profile (if enabled by admin). Links auto-expire after 7 days. The signup page shows the inviter's name and community stats.

### Slack Import

Full Slack workspace migration via `bin/rails slack:import[path/to/export.zip]`. Imports users, channels, messages, threads, and reactions. Placeholder user accounts can be claimed later. Idempotent — safe to re-run.

### Bot API

Sabha extends Campfire's write-only bot system into an autonomous-agent-ready API:

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

### Inbox System

Split inbox with dedicated views and real-time ActionCable channels:

- **Activity** — @mentions and @everyone
- **Threads** — replies to threads you're participating in
- **DMs** — direct message conversations
- **Bookmarks** — saved messages

Each inbox has its own query object (`app/models/inbox/`) and broadcast channel.

### Push Notifications & PWA

- **Web push** via VAPID — connection-aware delivery (skips users actively viewing the room)
- **PWA** — installable with dynamic manifest, service worker, badge API for unread count
- **Install prompt** — platform-specific instructions via Stimulus controller

### Authentication

Configurable via `AUTH_METHOD` environment variable:

| Method | Flow |
|---|---|
| **Password** (default) | Email + password with bcrypt |
| **OTP** | Email → 6-digit code → verified |

Also: email verification for new users, password reset, QR code session transfer between devices.

### DiceBear Avatars

Auto-generated avatars for users without profile photos. Users can shuffle to get a new random design. Configurable style via `DICEBEAR_STYLE` env var.

### Themes

Users select Light, Dark, or Auto from their profile. Applied before page render to avoid flash.

### Presence Tracking

`connected_at` on memberships with 60-second TTL. Three status tiers: online (green), away (yellow), offline (gray).

### Branding Customization

Full white-label via environment variables — app name, support email, PWA colors, icons. Custom CSS via admin panel. See [BRANDING.md](./BRANDING.md).

### Other

- **User streaks** — consecutive days of posting with tiered icons
- **Sound effects** — `/play name` syntax with ~50 built-in sounds
- **Bookmark indicators** — icon on bookmarked messages
- **System event messages** — room renames, member joins/leaves recorded as special messages
- **@everyone mentions** — broadcast mentions via `mentions_everyone` flag

---

## Architectural Changes

### AnyCable

Optional AnyCable-Go for WebSocket scaling (HTTP RPC mode, no gRPC). Benchmarks show 167x faster WebSocket connections and 2x message throughput vs ActionCable. Enabled by default.

### Solid Queue

SQLite-backed background jobs replacing Redis-backed alternatives. Runs inside Puma in development, as separate workers in production.

### Multi-Tenant SaaS Mode

Optional Rails engine in `saas/` for database-per-workspace isolation:

- PostgreSQL for shared data (identities, workspaces, sessions)
- SQLite per workspace for all app data
- Path-based routing (`/1000001/rooms/general`)
- OTP-only auth via GlobalIdentity
- Tenant context auto-propagated to jobs and channels

See [multi-tenant/](./multi-tenant/) docs. The `saas/` directory is under the [Sabha SaaS License](../saas/LICENSE), not MIT.

### Soft Deletion

Comprehensive soft deletion via `Deactivatable` concern (`active` boolean). Users use a `status` enum (`active`/`deactivated`/`banned`) instead. Room deactivation cascades to threads, memberships, and messages. DM memberships are preserved so other participants keep their history.

### 13 ActionCable Channels

| Channel | Purpose |
|---------|---------|
| `RoomChannel` | Message broadcasts |
| `PresenceChannel` | Online/offline tracking |
| `RoomListChannel` | Sidebar updates |
| `UserUnreadRoomsChannel` | Unread badges |
| `TypingNotificationsChannel` | Typing indicators |
| `HeartbeatChannel` | Keep-alive |
| `ReadRoomsChannel` | Mark as read |
| `UserInvolvementsChannel` | Notification preference changes |
| `InboxActivityChannel` | @mentions |
| `InboxThreadsChannel` | Thread replies |
| `InboxDirectMessagesChannel` | DMs |
| `InboxBookmarksChannel` | Bookmarks |
| `UnreadNotificationsChannel` | Unread count |

### Deployment

Three-container architecture: web (Puma + Redis + Solid Queue), AnyCable-Go, reverse proxy (kamal-proxy or Thruster). Deployed via Kamal or Docker Compose.

---

## Inherited from Small Bets Fork

Sabha was forked from [Gumroad's Small Bets fork](https://github.com/antiwork/smallbets), which added:

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

### Removed from Small Bets

| Feature | Reason |
|---------|--------|
| Video library | Removed Inertia.js/React infrastructure — Sabha is server-rendered only |
| Expert role | Removed expert directory and "answered" message functionality |
| Stats dashboard | Replaced with simpler user streaks |
| Room URL slugs | Users navigate via sidebar, not URL slugs |
| Room merge | Data integrity concerns |
| Email digest notifications | Removed (may revisit) |
| Marketing pages | Unauthenticated users redirect to sign-in |
