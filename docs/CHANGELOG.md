# Sabha Changelog

Chronological list of features added to Sabha. Sabha is built on [Once Campfire](https://once.com/campfire) via the [Small Bets fork](https://github.com/antiwork/smallbets).

For a side-by-side comparison, see [CAMPFIRE_VS_SABHA.md](https://github.com/sabha-co/sabha/blob/main/docs/CAMPFIRE_VS_SABHA.md).

---

## From SmallBets (Feb 2024 - Oct 2025)

These features were built by [Antiwork](https://github.com/antiwork) for their Small Bets community and inherited by Sabha.

- **Email support** — use Resend for transactional emails
- **Threads** — reply to any message to start a focused discussion (Mar 2024)
- **Mentions tab** — dedicated sidebar view for @mentions (Feb 2024)
- **Bookmarks** — save messages, view from sidebar (Feb 2024)
- **Unread indicators** — "new since last visit" line in rooms (Feb 2024)
- **Mark as unread** — revert read status on any message (Feb 2024)
- **User blocking** — block users from sending you DMs (Feb 2024)
- **One-click reboost** — repeat someone else's boost quickly (Feb 2024)
- **@everyone mentions** — notify all members in a room (Oct 2025)
- **Soft deletion** — rooms, messages, memberships, boosts, bookmarks (Oct 2025)
- **Bot API extras** — everything webhook, DM creation, user mentions (Feb 2024)
- **Room search** — filter rooms by typing in the sidebar (2024)
- **Rich text on mobile** — rich-text editing options on mobile (2024)

---

## Sabha (Nov 2025 - present)

### Nov 2025

- **Branding customization** — white-label via environment variables (app name, email, PWA colors, icons)
- **Admin settings UI** — toggle room creation, DM, and invite link permissions from the web UI
- **Jemalloc** — production memory allocator for lower memory usage
- **Theme switch** — Light, Dark, or Auto from your profile

### Dec 2025

- **User banning** — ban users with IP blocking, session termination, message soft-deletion
- **Password authentication** — brought back email + password login alongside OTP
- **Email verification** — new users must verify email before accessing the app
- **Password reset** — "Forgot password?" flow with expiring reset links

### Jan 2026

- **Slack import (Experimental)** — migrate users, channels, messages, threads, and reactions from a Slack export.
- **Personal invite links** — members generate their own invite links (if enabled by admin)
- **AnyCable** — high-performance Go WebSocket server replacing ActionCable (10x faster connections, 2x throughput)
- **Solid Queue** — SQLite-backed background jobs replacing in-process execution
- **Tailwind CSS v4** — upgraded from v3 with pnpm build pipeline
- **YJIT** — Ruby JIT compiler enabled in production for better performance
- **DiceBear avatars** — auto-generated avatars for users without profile photos
- **User streaks** — consecutive posting days with tiered streak icons
- **Member management** — admin panel with role management, badges, search, banned users list
- **Email change** — change email with verification sent to both old and new addresses
- **Bookmark improvements** — icon on bookmarked messages with real-time updates
- **Soft deletion improvements** — proper reactivation, ban cleanup, deactivated user blocking

### Feb 2026

- **Room starring** — star rooms to pin them in your sidebar
- **Activity notifications refactor** — notification system for the activity/mentions tab
- **Push notification improvements** — VAPID web push with connection-aware delivery
- **PWA improvements** — installable app with dynamic manifest, service worker, badge API
- **Cloudflare Turnstile** — CAPTCHA on signup flows
- **Authenticated file downloads** — Active Storage files served only to signed-in users
- **OKLch color tokens** — design token system for light/dark theming
- **@tailwindcss/cli** — direct CLI compilation for CSS builds

### Mar 2026

- **Bot API upgrade** — self-registration, API discovery, message reading, webhook timeout, SSRF protection. Ready for LLM agents.
- **Welcome messages** — automatic welcome message for new members
- **Chat animations** — message arrival, popup menus, thread panel easing
- **Accessibility** — pinch to zoom, aria-live regions, reduced motion support
- **Badge management** — dedicated admin page for managing user badges
- **Inline DM compose** — start new direct messages directly from the DM index page

### Apr 2026

- **More things bots can do** — edit and delete their own messages, react with emoji, manage room members, create and archive rooms, and search across conversations
- **Real-time bots** — bots connect to Sabha directly and receive messages instantly using websockets, no public webhook URL required
- **OpenClaw plugin** — new [OpenClaw plugin](https://github.com/sabha-co/openclaw-sabha) for Sabha integration
- **Bots in threads and DMs** — bots added to a thread or DM now receive every message, just like human members
- **Bot avatars and management** — cleaner bot admin page, auto-generated robot avatars, bots shown in the members list

### May 2026

- **Email notifications** — opt in to bundled missed-mention emails (hourly or daily) and a weekly workspace activity digest.
- **Notification preferences** — dedicated profile area for notification settings: global mode, email frequency, digest opt-in, push toggle
- **SSO** — self-hosted Sabhas can hand off sign-in to an external identity provider; Sabha SaaS can act as that provider for self-hosted installs

### Multi-tenant SaaS features

> The `saas/` directory is under the [Sabha SaaS License](https://github.com/sabha-co/sabha/blob/main/saas/LICENSE), not MIT.

- **Database-per-workspace isolation** — PostgreSQL for shared data, SQLite per workspace
- **Path-based routing** — `/1000001/rooms/general` with transparent URL generation
- **GlobalIdentity** — cross-workspace single sign-on with OTP-only auth
- **Workspace provisioning** — guided setup flow with invite step
- **Platform superadmin dashboard** — manage all workspaces from one place
- **Per-workspace storage tracking** — event-sourced usage monitoring
- **AWS SES support** — alternative email provider alongside Resend
- **SaaS landing page** — marketing page for multi-tenant deployments
- **Welcome email** — sent to workspace creator after provisioning
- **Tenant-aware jobs and channels** — Solid Queue and ActionCable auto-propagate tenant context
- **Workspace backups** — automated backups to R2 cloud storage with restore support
- **Self-host export** — admins can download their workspace database to migrate to a self-hosted Sabha install
- Disposable email addresses blocked on SaaS signup
- **Ban and deactivate flow** — banned or deactivated members are signed out right away and emailed about it; admins can still find them in the member list to undo the action