# Sabha

A community-driven fork of [Small Bets](https://github.com/antiwork/smallbets) that makes it easy to run your own branded community. All branding (app name, logos, colors, emails) is configurable through environment variables—no code changes required.

Based on [Once Campfire](https://github.com/basecamp/once-campfire/), a Ruby on Rails chat application built by [37signals](https://once.com/campfire), with additional features from Small Bets. See [smallbets-mods.md](smallbets-mods.md) for a list of modifications.

<img width="1297" height="867" src="https://github.com/user-attachments/assets/a615c6df-1952-49af-872a-793743e6ad6e" />

This project combines the simplicity of Campfire with passwordless authentication and community features. Perfect for running course communities or private group chats.

If you find a bug or have a feature request, please [post an issue](https://github.com/sabha-co/sabha/issues/new). Contributions welcome!

## Running in development

### Prerequisites

- Ruby 4.0.1 (check with `ruby --version`)
- Redis server
- SQLite3
- Node.js with pnpm for Tailwind CSS builds

### Customizing Branding

To run your own branded community, copy `.env.sample` to `.env` and configure:

```bash
APP_NAME="Your Community Name"
APP_HOST="chat.yourdomain.com"
SUPPORT_EMAIL="support@yourdomain.com"
MAILER_FROM_NAME="Your Community"
MAILER_FROM_EMAIL="noreply@yourdomain.com"
```

See [BRANDING.md](BRANDING.md) for complete customization options.

### Setup

```bash
bin/setup
```

Start the app in development:

```bash
bin/dev
```

This starts both the Rails server and Vite dev server using Foreman (via Procfile.dev).

The `bin/setup` script installs Ruby gems and Node packages (via `pnpm install`), prepares the database, and configures the application.
If you skip `bin/setup`, install frontend dependencies manually with `pnpm install`.

All CSS is managed through Vite. Tailwind processes styles from `app/frontend/entrypoints/application.css`, which is automatically rebuilt during development.

## Running in production

Sabha uses [Kamal](https://kamal-deploy.org/docs/installation/) for deployment. A modern tool that provides zero-downtime deployments with Docker.

### Prerequisites

- A Linux server (Ubuntu 20.04+ recommended)
- Docker installed on the server
- A domain name pointing to your server
- Docker Hub account (or another container registry)
- Kamal CLI installed locally (install via `gem install kamal`)

### Initial Server Setup

1. **Initialize Kamal (creates `.kamal/secrets` if missing):**

   ```bash
   kamal init
   ```

2. **Configure environment variables:**
   Edit `.kamal/secrets` and add your production secrets, for example:

   ```bash
   # Registry
   KAMAL_REGISTRY_PASSWORD=your-docker-hub-password
   REGISTRY_USERNAME=your-docker-hub-username

   # Server + domain
   SERVER_IP=your-server-ip
   PROXY_HOST=your-domain.com

   # Application secrets (generate with: rails secret)
   SECRET_KEY_BASE=your-rails-secret-key
   RESEND_API_KEY=your-resend-api-key
   VAPID_PUBLIC_KEY=your-vapid-public-key
   VAPID_PRIVATE_KEY=your-vapid-private-key
   COOKIE_DOMAIN=your-domain.com
   ```

3. **Initial deployment:**
   ```bash
   kamal setup    # Sets up Docker, builds image, starts services
   ```

### Subsequent Deployments

```bash
kamal deploy   # Zero-downtime deployment
```

### Automated Deployments

This repository includes GitHub Actions for automatic deployment:

1. **Set GitHub Secrets** in your repository settings:
   - `SSH_PRIVATE_KEY` - SSH key for server access
   - `SERVER_IP` - Your production server IP
   - `DOMAIN` - Your domain name (PROXY_HOST)
   - `DOCKER_USERNAME` & `DOCKER_PASSWORD` - Docker Hub credentials
   - `SECRET_KEY_BASE` - Rails encryption key
   - `RESEND_API_KEY` - Email delivery service
   - `VAPID_PUBLIC_KEY` & `VAPID_PRIVATE_KEY` - Push notifications
   - `COOKIE_DOMAIN` - Your domain for cookies

2. **Deploy automatically:**
   - Push to `master` branch for automatic deployment
   - Or use "Deploy with Kamal" workflow for manual deployment

### Alternative: Manual Docker Deployment

If you prefer not to use Kamal, you can deploy manually with Docker:

```bash
# Build and run
docker build -t sabha .
docker run -p 3000:3000 \
  -e RAILS_ENV=production \
  -e SECRET_KEY_BASE=your-secret-key \
  -v /path/to/storage:/rails/storage \
  sabha
```

### Environment Variables Reference

| Variable                       | Purpose                     | Required |
| ------------------------------ | --------------------------- | -------- |
| `SECRET_KEY_BASE`              | Rails encryption key        | ✅       |
| `RESEND_API_KEY`               | Email delivery via Resend   | ✅       |
| `VAPID_PUBLIC_KEY`             | Web push notifications      | ✅       |
| `VAPID_PRIVATE_KEY`            | Web push notifications      | ✅       |
| `COOKIE_DOMAIN`                | Session cookies domain      | ✅       |

✅ = Required for production deployment

### Database Backups

**IMPORTANT:** Sabha does not include automatic database backups out of the box. You must implement your own backup strategy.

**Recommended Options:**

1. **Volume Snapshots** - Use your cloud provider's snapshot feature (DigitalOcean, AWS, etc.)

2. **Periodic Backups** - Schedule cron jobs or scripts to backup the SQLite database:
   ```bash
   # Example: Daily backup at 2 AM
   0 2 * * * tar -czf /backups/sabha-$(date +\%Y\%m\%d).tar.gz /disk/sabha/db/production.sqlite3
   ```

See [DEPLOYMENT.md](docs/DEPLOYMENT.md#database-backups) for detailed backup strategies.


## Credits

Based on [Once Campfire](https://github.com/basecamp/once-campfire/) by 37signals. Includes modifications from [Small Bets](https://github.com/antiwork/smallbets). See [campfire-ce-changelog.md](campfire-ce-changelog.md) for details.

## Contributing

Open an [issue](https://github.com/sabha-co/sabha/issues/new) for bugs or feature requests.

## License

Sabha is available under the MIT license. See LICENSE for details.