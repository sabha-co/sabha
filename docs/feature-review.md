# Sabha Feature Review Checklist

Sabha is a fork of Once Campfire with 59 additional features. This document lists every feature for structured evaluation.

## Status Legend

| Status | Meaning |
|--------|---------|
| **Keep** | Feature is solid, no changes needed |
| **Review** | Needs deeper look or refactoring |
| **Remove** | Should be removed |
| **Refine** | Keep but needs improvement |
| **Keep** | Not yet evaluated (default) |

---

## 1. Core Messaging Enhancements (7)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 1 | **Threading** — Reply chains with `Rooms::Thread` sub-rooms, thread panel sidebar, parent message context | Keep | |
| 2 | **Message Bookmarks** — Save/unsave messages, dedicated inbox tab | Review | |
| 3 | **Soft Deletion** — Messages/rooms/memberships deactivated not destroyed, preserved in DB | Refine | Add admin UI to restore deleted messages/rooms |
| 4 | **Message Unreads** — Mark messages/threads as unread manually | Keep | |
| 5 | **Boost Groups** — Boost reactions show contributor avatars, grouped display | Keep | |
| 6 | **@everyone Mentions** — Admin-only broadcast mentions in open rooms | Review | |
| 7 | **Message Edit Shortcut** — Arrow-up to edit last message | Review | |

## 2. Inbox / Activity System (6)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 8 | **Activity Inbox** — Centralized hub for @mentions, boosts, thread replies | Keep | |
| 9 | **DM Inbox** — Organized direct message conversations tab | Keep | |
| 10 | **Threads Inbox** — Thread replies tracking tab | Keep | |
| 11 | **Bookmarks Inbox** — Saved messages tab | Review | |
| 12 | **Messages Inbox** — Message search tab | Review | |
| 13 | **Inbox Clear** — Mark all as read | Review | |

## 3. Room Management (6)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 14 | **Room Browse** — Discover and join public rooms | Keep | |
| 15 | **Room Stars / Favorites** — Pin rooms to a Favorites sidebar section | Keep | |
| 16 | **Room Access Toggle** — Switch rooms between public/private | Keep | |
| 17 | **Member Management** — Admin add/remove members from rooms | Keep | |
| 18 | **Self-Service Join/Leave** — Users join/leave rooms without admin | Keep | |
| 19 | **Hidden Rooms** — Sidebar section for muted/hidden rooms | Keep | |

## 4. Sidebar & Navigation (4)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 20 | **Sidebar Overhaul** — Vertical right-side toolbar with organized sections (Favorites, All Rooms, DMs) | Refine | |
| 21 | **Quick Access Tools** — Activity, DMs, Threads, Bookmarks, Bell, Profile links in sidebar | Review | |
| 22 | **Unread Badges** — Dynamic unread indicators on rooms and sidebar sections | Keep | |
| 23 | **Return-to-Latest Button** — Pulsing scroll-to-bottom when scrolled away | Keep | |

## 5. Authentication & Security (5)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 24 | **OTP / Passwordless Auth** — Email-based 6-digit code login via `AuthToken` | Keep | |
| 25 | **Password Reset** — Self-service password reset flow | Keep | |
| 26 | **Email Verification** — Required verification for new users | Keep | |
| 27 | **Dual Auth Method** — Admin-configurable toggle between password and OTP | Keep | |
| 28 | **Cloudflare Turnstile** — Bot protection on auth forms | Keep | |

## 6. User Features (10)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 29 | **User Blocking** — Block/unblock users | Review | |
| 30 | **User Badges** — Achievement/role badges with admin assignment | Review | |
| 31 | **DiceBear Avatars** — Auto-generated avatars for users without photos | Keep | |
| 32 | **User Preferences** — Notification and display preferences | Review | |
| 33 | **User Message History** — View a user's past messages | Keep | |
| 34 | **User Search History** — Track and clear search history | Keep | |
| 35 | **Quick Profile Popover** — Hover/click profile cards with social links | Refine | |
| 36 | **Role Badges** — Visual role indicators on messages | Review | |
| 37 | **Invite Links** — Shareable workspace invite URLs | Keep | |
| 38 | **Flexible Join Codes** — Multiple codes with usage limits and expiration |  Review | |

## 7. Theming & UI (5)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 39 | **Theme Toggle** — User-selectable dark/light mode with persistence | Keep | |
| 40 | **Tailwind CSS v4** — Complete styling system migration from vanilla CSS | Keep | |
| 41 | **PWA Support** — Progressive Web App install instructions and settings | Keep | |
| 42 | **Lightbox** — Modal image/media viewer | Keep | |
| 43 | **OpenGraph Embeds** — Link preview cards in messages | Review | |

## 8. Admin / Account (3)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 44 | **User Management UI** — Full user list with inline role toggles | Keep | |
| 45 | **Admin Settings Panel** — Expanded admin-only controls | Keep | |
| 46 | **Branding System** — Configurable APP_NAME, colors, logos via env vars |  Review | |

## 9. Infrastructure (6)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 47 | **SaaS Multi-Tenancy** — Full `saas/` engine with per-workspace SQLite databases, PostgreSQL untenanted DB, path-based routing | Keep | |
| 48 | **Solid Queue** — SQLite-backed job queue (replaced Resque) | Keep | |
| 49 | **AnyCable Support** — High-performance WebSocket option | Keep | |
| 50 | **Hotwire Native Bridge** — Native mobile app support | Keep | |
| 51 | **Webhook Events** — Event log for bot/webhook debugging | Review | |
| 52 | **Analytics** — Umami integration support | Keep | |

## 10. Real-time Channels (7)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 53 | **InboxActivityChannel** — Live activity notifications | Keep | |
| 54 | **InboxBookmarksChannel** — Live bookmark updates | Keep | |
| 55 | **InboxDirectMessagesChannel** — Live DM inbox updates | Keep | |
| 56 | **InboxThreadsChannel** — Live thread reply updates | Keep | |
| 57 | **UserUnreadRoomsChannel** — Per-user unread counts | Keep | |
| 58 | **UserInvolvementsChannel** — Involvement settings updates | Keep | |
| 59 | **RoomListChannel** — Sidebar room list updates | Keep | |
