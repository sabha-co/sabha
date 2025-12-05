# Architecture: Campfire-CE vs Small Bets

This document outlines the architectural differences between Campfire-CE and the upstream Small Bets fork.

## Philosophy

| | Small Bets | Campfire-CE |
|---|---|---|
| **Focus** | All-in-one community platform (chat + video library + experts + feed) custom made for closed/paid communities | Pure chat platform |
| **Frontend** | Hybrid Rails + React/Inertia.js | Traditional Rails + Hotwire |
| **Complexity** | Feature-rich, more dependencies | Simpler, maintainable |

## Frontend Architecture

### Small Bets
- **Vite + React + TypeScript** with Inertia.js for SPA pages
- React pages in `app/frontend/pages/library/` and `app/frontend/pages/feed/`
- Full React component library (`app/frontend/components/ui/`)
- `@vitejs/plugin-react` in Vite config
- Inertia handles React app bootstrapping with SSR support

### Campfire-CE
- **Vite + Tailwind CSS only** (no React/Inertia)
- Pure server-rendered views with Hotwire (Turbo + Stimulus)
- Vite used only for Tailwind v4 processing
- JavaScript via Importmap (Stimulus controllers)

**Why:** Removing React/Inertia eliminates ~8,000 lines of code and significant complexity while keeping core chat functionality intact.


## Features Removed

| Feature | Description | Reason |
|---------|-------------|--------|
| **Video Library** | Netflix-style video browsing with Vimeo integration | Small Bets-specific, requires Vimeo account |
| **Live Events** | Countdown banners for scheduled events | No admin UI, untested |
| **Experts Directory** | Expert users with special privileges | Small Bets-specific |
| **Feed System** | Automated feed cards | Small Bets-specific |
| **OpenAI Integration** | AI features via `ruby-openai` gem | Small Bets-specific, can relook in the future |


## Features Added

| Feature | Description |
|---------|-------------|
| **Admin Settings UI** | Configure auth method and permissions from `/account/edit` |
| **User Banning** | Ban users with IP blocking and content removal |
| **Email Verification** | Required email verification for new users |
| **Password Reset** | Self-service password reset flow |


## Runtime & Dependencies

| | Small Bets | Campfire-CE |
|---|---|---|
| **Ruby** | 3.3.1 | 3.4.5 |
| **Puma** | ~6.4 | ~7.1 |
| **SQLite3** | ~1.4 | >= 2.8 |
| **Memory Allocator** | Standard | Jemalloc |
| **Rails** | ~7.2 | Edge (8.2) |
| **Gem Sources** | GitHub edge versions | Stable releases |
| **React/Inertia** | Yes | No |
| **TypeScript** | Yes | No |


## Database Schema

### Removed Tables
- `library_classes` - Course content
- `library_sessions` - Video sessions
- `library_watch_histories` - Watch progress
- `library_categories` - Content categories
- `library_classes_categories` - Join table
- `live_events` - Scheduled events

### Added Tables
- `bans` - IP-based user bans


## Configuration

### Environment Variables

Campfire-CE has comprehensive environment variable support for white-labeling:

```bash
# Branding
APP_NAME=MyCommunity
APP_SHORT_NAME=MC
APP_DESCRIPTION="My community chat"
APP_HOST=chat.example.com

# Contact
SUPPORT_EMAIL=support@example.com
MAILER_FROM_NAME=MyCommunity
MAILER_FROM_EMAIL=noreply@example.com

# Visual
THEME_COLOR=#3B82F6
BACKGROUND_COLOR=#ffffff

# Security
CSP_FRAME_ANCESTORS=https://example.com
COOKIE_DOMAIN=.example.com
```

Small Bets has minimal environment configuration with hardcoded branding.


## Docker/Deployment

### Campfire-CE Optimizations
- Jemalloc memory allocator (`LD_PRELOAD="/usr/local/lib/libjemalloc.so"`)
- Explicit build cleanup (`rm -rf node_modules tmp/cache .git`)
- Node.js 22.x via NodeSource
- OCI image metadata labels
- Smaller final image size


## Shared Features

Both codebases include these Small Bets modifications:

- Mentions tab and @everyone mentions
- Bookmarks
- Boosts/Reboosts
- Block users
- Stats page
- Soft deletion
- Enhanced Bot API
- Threaded discussions
- Email notifications for unread mentions
- Room search
- "New since last visit" indicator
- Mark messages as unread


## File Structure Comparison

```
smallbets/                          campfire-ce/
├── app/frontend/                   ├── app/frontend/
│   ├── pages/                      │   ├── pages/          (empty)
│   │   ├── library/   (React)      │   │
│   │   └── feed/      (React)      │   │
│   ├── components/ui/ (React)      │   ├── components/     (empty)
│   └── entrypoints/                │   └── entrypoints/
│       ├── inertia.ts              │       ├── application.js
│       └── application.css         │       └── application.css
├── Gemfile                         ├── Gemfile
│   └── inertia_rails              │   └── (no inertia)
│   └── ruby-openai                │   └── (no openai)
└── package.json                    └── package.json
    └── react, @inertiajs/react        └── (no react)
```


## Migration Path

When pulling updates from Small Bets upstream:

1. **Skip** changes to removed features (library, feed, experts, live_events)
2. **Review** changes to shared features (mentions, bookmarks, etc.)
3. **Apply** bug fixes and security patches
4. **Test** thoroughly before deploying

The simplified architecture makes it easier to maintain and customize for your community's needs.
