# Sabha

A self-hosted group chat for communities. Built with Rails, Hotwire, and SQLite.

Sabha is a fork of [Campfire](https://once.com/campfire) by 37signals, adding threads, mentions, DMs, an activity inbox, and everything else needed to run a community without handing your members over to a platform. See [what Sabha adds to Campfire](docs/CAMPFIRE_VS_SABHA.md).

![Sabha app — rooms, threads, and community chat](app/assets/images/screenshots/sabha-screenshot.png)

## Why Sabha?

- **You own everything** — server, data, domain, branding
- **No per-seat pricing** — host as many members as your server handles
- **SQLite in production** — no database server to manage
- **One-command deploy** — Kamal or Docker Compose on a $10/month VPS
- **Slack Migration** — Easy migration from Slack to Sabha
- **OpenClaw Integration ready** — Integration with OpenClaw for AI features

## Features

- Rooms (public, private, DMs)
- Threaded replies on any message
- @mentions and `@everyone` with notification badges
- Activity inbox for mentions, boosts, and thread replies
- Rich text, file attachments, and sounds
- Full-text search (SQLite FTS5)
- Typing indicators and presence
- Web push notifications
- Bookmarks and boosts
- Customizable branding (name, logos, colors, emails)
- Password or passwordless email OTP authentication option

## Tech Stack

Rails 8 with Hotwire/Turbo, ActionCable for real-time, Tailwind CSS v4 via `@tailwindcss/cli`, Importmap for JS, Solid Queue for background jobs. SQLite3 everywhere — app, cache, queue.

Room types via STI (`Rooms::Open`, `Rooms::Closed`, `Rooms::Direct`, `Rooms::Thread`). Soft deletion via `Deactivatable` concern. Stateless mentions parsed from ActionText HTML.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full breakdown.

## Self-Hosting

### Kamal (recommended)

Zero-downtime Docker deployments with AnyCable (high-performance WebSockets):

```bash
kamal setup    # First deploy
kamal deploy   # Subsequent deploys
```

### Docker Compose

Pre-built images at `ghcr.io/sabha-co/sabha`. No need to clone the repo.

```bash
# On your server
mkdir -p ~/sabha && cd ~/sabha
# Create docker-compose.yml and .env (see docs/DEPLOYMENT.md)
docker compose up -d
```

Requires a VPS with 2GB+ RAM, a domain, and Docker. See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the full guide including TLS, backups, and upgrades.

## Development

### Prerequisites

- Ruby 4.0.1
- SQLite3
- Redis
- Node.js + pnpm (Tailwind CSS compilation)

### Setup

```bash
bin/setup    # Install deps, prepare DB, build CSS
bin/dev      # Start dev server
```

### Testing

```bash
bin/rails test                         # Full suite
bin/rails test test/models/user_test.rb # Single file
```

## Documentation

| Doc | What it covers |
|-----|---------------|
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Docker Compose, Kamal, backups, upgrades |
| [DEVELOPMENT.md](docs/DEVELOPMENT.md) | Dev setup, testing, code structure |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Models, real-time, room system, auth |
| [BRANDING.md](docs/BRANDING.md) | Environment variables, icons, custom CSS |
| [CHANGELOG.md](docs/CHANGELOG.md) | Feature history |
| [CAMPFIRE_VS_SABHA.md](docs/CAMPFIRE_VS_SABHA.md) | What Sabha adds to Campfire |

## Contributing

Bug reports and pull requests are welcome. [Open an issue](https://github.com/sabha-co/sabha/issues/new) first to discuss what you'd like to change.

## Credits

Built on [Once Campfire](https://github.com/basecamp/once-campfire/) by [37signals](https://37signals.com). Some additional features from [Small Bets](https://github.com/antiwork/smallbets) by Gumroad.

## License

Sabha is available under the [MIT License](LICENSE.md). The multi-tenant SaaS engine (`saas/`) is licensed separately — see [saas/LICENSE](saas/LICENSE).
