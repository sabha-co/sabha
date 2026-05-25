# Sabha

Sabha is an open-source, self-hosted chat platform for **friends, groups, and communities** — a calm alternative to Discord and Slack. Run it on your own VPS and own every byte. No per-seat pricing, no message limits, no platform telling you what your community is worth.

[![Tests](https://github.com/sabha-co/sabha/actions/workflows/test.yml/badge.svg)](https://github.com/sabha-co/sabha/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/github/license/sabha-co/sabha?color=%239944ee)](LICENSE.md)
[![GitHub Stars](https://img.shields.io/github/stars/sabha-co/sabha?style=flat&logo=github)](https://github.com/sabha-co/sabha/stargazers)

![Sabha app — rooms, threads, and community chat](app/assets/images/screenshots/sabha-screenshot.png)

## Features

**Real-time chat** — public rooms, private rooms, direct messages, threaded replies, `@mentions`, typing indicators, and presence. All real-time over WebSockets.

**Flexible authentication** — password, passwordless email OTP, or external SSO. All three coexist; pick what fits your community.

**Activity inbox** — a dedicated sidebar surface for mentions, boosts, and thread replies. Nothing important hides at the bottom of a busy room.

**Email notifications** — Calm by default; every email is opt-in.

**Bot / agent API** — REST + WebSocket surface for LLM agents with HMAC-signed webhooks. First-party [OpenClaw plugin](https://github.com/sabha-co/openclaw-sabha) drops an LLM into any room with one invite link.

**Installable PWA** — works on iOS, Android, and desktop with VAPID web push and unread badge counts. No app stores in the loop.

**Your brand** — name, logos, PWA colors, and support email are configurable via environment variables and the admin UI. The community feels like yours.

**Slack migration** — import users, channels, messages, threads, and reactions from a Slack export. Idempotent and safe to re-run.

**One-command deploy** — Kamal or Docker Compose on a single small VPS. SQLite for app data and full-text search; no managed database to operate.

## Architecture

Sabha is a Rails 8 monolith. The frontend is Hotwire/Turbo + Importmap + Tailwind CSS v4. Real-time delivery runs through AnyCable. Background jobs run on Solid Queue, backed by SQLite. Storage is split: SQLite3 for app data, jobs, and full-text search; Redis for the cache store and cable pubsub.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full breakdown.

## Screenshots

<!-- TODO: add screenshots here -->
_Coming soon._

## Getting started

The [deployment guide](docs/DEPLOYMENT.md) covers Kamal and Docker Compose with TLS, backups, and upgrades. The full doc index lives in [docs/](docs/).

The optional multi-tenant SaaS engine is documented under [docs/multi-tenant/](docs/multi-tenant/) and licensed separately — see [saas/LICENSE](saas/LICENSE).

## Development

### Prerequisites

- Ruby 4.0.1
- SQLite3
- Redis
- Node.js + pnpm (for Tailwind CSS compilation)

### Setup

```bash
bin/setup    # Install deps, prepare DB, build CSS
bin/dev      # Start dev server
```

### Testing

```bash
bin/rails test                          # Full self-hosted suite
bin/rails test test/models/user_test.rb # Single file
SAAS=true bin/rails test saas/test/     # SaaS suite
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the full guide.

## Help and discussion

#### Bug reports and feature requests

Bug reports and feature requests can be posted on [GitHub Issues](https://github.com/sabha-co/sabha/issues).

#### Contributing

Pull requests are welcome. Please open an issue first to discuss substantial changes. Run the test suite before submitting; for changes that touch the `saas/` engine, run both the self-hosted suite and `SAAS=true bin/rails test saas/test/`.

## Credits

Built on [Once Campfire](https://github.com/basecamp/once-campfire/). Some additional features inherited from the [Small Bets](https://github.com/antiwork/smallbets) fork by Antiwork.

## License

Sabha is available under the [MIT License](LICENSE.md). The multi-tenant SaaS engine in `saas/` is licensed separately — see [saas/LICENSE](saas/LICENSE).
