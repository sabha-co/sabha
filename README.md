# Sabha

A self-hosted, open-source chat platform for communities. Like Slack or Discord, but you own the server, the data, the domain, and the branding.

Built on [Campfire](https://once.com/campfire) by 37signals — the team behind Basecamp and HEY — with a lot of additional features. Sabha takes the rock-solid Campfire foundation and adds threads, mentions, DMs, an activity inbox, and everything else you need to run an open community without handing your members over to a platform.

<img width="1297" height="867" src="https://github.com/user-attachments/assets/a615c6df-1952-49af-872a-793743e6ad6e" />

## Features

- **Rooms** — Public, private, and direct message rooms
- **Threaded discussions** — Reply to any message in a dedicated thread
- **@mentions** — Mention users or `@everyone`, with notification badges
- **Rich text messages** — Formatting, file attachments, and sounds via ActionText
- **Activity inbox** — Dedicated tab for mentions, boosts, and thread replies
- **Boosts** — React to and reshare messages
- **Bookmarks** — Save messages for later
- **Full-text search** — Fast search powered by SQLite FTS5
- **Typing indicators** — See who's typing in real-time
- **Push notifications** — Web push via VAPID
- **Presence** — See who's online
- **Customizable branding** — App name, logos, colors, and emails via environment variables
- **Dual auth** — Password or passwordless email OTP, configurable per workspace

## Tech Stack

- Ruby on Rails with Hotwire/Turbo
- ActionCable (WebSockets) for real-time
- SQLite3 in production
- Tailwind CSS v4
- Solid Queue for background jobs
- Kamal for deployment

## Getting Started

### Prerequisites

- Ruby 4.0.1
- SQLite3
- Redis (for ActionCable)
- Node.js + pnpm (for Tailwind CSS)

### Setup

```bash
bin/setup    # Installs gems, pnpm packages, prepares DB, builds CSS
bin/dev      # Start the dev server
```

For active CSS development, run `pnpm run build:css:watch` in a separate terminal.

### Branding

Copy `.env.sample` to `.env` and configure:

```bash
APP_NAME="Your Community"
APP_HOST="chat.yourdomain.com"
SUPPORT_EMAIL="support@yourdomain.com"
MAILER_FROM_NAME="Your Community"
MAILER_FROM_EMAIL="noreply@yourdomain.com"
```

See [docs/BRANDING.md](docs/BRANDING.md) for all customization options.

## Production Deployment

Sabha uses [Kamal](https://kamal-deploy.org/) for zero-downtime Docker deployments.

### Quick Start

1. Install Kamal: `gem install kamal`
2. Configure secrets in `.kamal/secrets`:
   ```bash
   KAMAL_REGISTRY_PASSWORD=your-docker-hub-password
   SERVER_IP=your-server-ip
   PROXY_HOST=your-domain.com
   SECRET_KEY_BASE=$(rails secret)
   RESEND_API_KEY=your-resend-api-key
   VAPID_PUBLIC_KEY=your-vapid-public-key
   VAPID_PRIVATE_KEY=your-vapid-private-key
   ```
3. Deploy:
   ```bash
   kamal setup    # First deploy
   kamal deploy   # Subsequent deploys
   ```

### Docker (without Kamal)

```bash
docker build -t sabha .
docker run -p 3000:3000 \
  -e RAILS_ENV=production \
  -e SECRET_KEY_BASE=your-secret-key \
  -v /path/to/storage:/rails/storage \
  sabha
```

### Required Environment Variables

| Variable | Purpose |
|----------|---------|
| `SECRET_KEY_BASE` | Rails encryption key |
| `RESEND_API_KEY` | Email delivery via Resend |
| `VAPID_PUBLIC_KEY` | Web push notifications |
| `VAPID_PRIVATE_KEY` | Web push notifications |

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed deployment and backup strategies.

## Multi-Tenant (SaaS) Mode

Sabha also supports a multi-tenant mode with database-per-workspace isolation, powered by the [`activerecord-tenanted`](https://github.com/basecamp/activerecord-tenanted) gem.

## Contributing

Bug reports and pull requests are welcome. Please [open an issue](https://github.com/sabha-co/sabha/issues/new) first to discuss what you'd like to change.

## Credits

Built on [Once Campfire](https://github.com/basecamp/once-campfire/) by [37signals](https://37signals.com). Community features from [Small Bets](https://github.com/antiwork/smallbets) by Gumroad.

## License

Sabha is available under the [MIT License](LICENSE.md).
