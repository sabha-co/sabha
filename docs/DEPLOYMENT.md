# Deploying Sabha

Deploy Sabha on your own VPS. Full control, own your data, server costs only (~$5-20/month).

For multi-tenant SaaS deployment, see [multi-tenant/DEPLOYMENT.md](./multi-tenant/DEPLOYMENT.md).

### Requirements

- A VPS with 2GB+ RAM (DigitalOcean, Hetzner, Linode, etc.)
- A domain name pointing to your server
- Basic command-line familiarity

### Quick Start with Docker

**1. Get a server and point your domain to it**

Any VPS provider works. Ubuntu 22.04+ recommended.

**2. Install Docker**

```bash
curl -fsSL https://get.docker.com | sh
```

**3. Clone and configure**

```bash
git clone https://github.com/sabha-co/sabha.git
cd sabha
cp .env.sample .env
nano .env
```

**4. Set your environment variables**

See `.env.sample` for a complete reference. Key variables:

```bash
# Domain
APP_HOST=chat.yourdomain.com

# Security
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Branding
APP_NAME=My Community
APP_SHORT_NAME=Community
APP_DESCRIPTION=A place for our community to connect

# Email (get API key from resend.com)
RESEND_API_KEY=your_resend_api_key
SUPPORT_EMAIL=support@yourdomain.com
MAILER_FROM_NAME=My Community
MAILER_FROM_EMAIL=noreply@yourdomain.com

# Web Push (generate with: npx web-push generate-vapid-keys)
VAPID_PUBLIC_KEY=your_public_key
VAPID_PRIVATE_KEY=your_private_key

# AnyCable (enabled by default, requires a secret)
ANYCABLE_SECRET=$(openssl rand -hex 32)

# Authentication method: "password" (default) or "otp"
AUTH_METHOD=password

# Cookie domain (set to your domain for production)
COOKIE_DOMAIN=chat.yourdomain.com
```

**5. Start**

```bash
docker compose up -d
```

Your community is live at `https://chat.yourdomain.com`

---

### Deploying with Kamal

For zero-downtime deployments, use [Kamal](https://kamal-deploy.org/).

**Setup**

```bash
# Install Kamal
gem install kamal

# Prepare your server
ssh root@your-server "curl -fsSL https://get.docker.com | sh && mkdir -p /disk/sabha"

# Configure secrets
cp .env.sample .kamal/secrets
nano .kamal/secrets  # Add SERVER_IP, PROXY_HOST, and other vars

# Deploy
kamal setup
```

**Common commands**

```bash
kamal deploy              # Deploy updates
kamal app logs -f         # Follow logs
kamal app exec 'bin/rails console'  # Rails console
kamal app stop            # Stop app
kamal app boot            # Start app
```

**Kamal configuration**

The repo includes `config/deploy.yml`:

```yaml
service: sabha
image: sabha

servers:
  web:
    - <%= ENV.fetch("SERVER_IP") %>

proxy:
  ssl: true
  host: <%= ENV.fetch("PROXY_HOST") %>
  app_port: 3000

registry:
  server: localhost:5000

volumes:
  - "/disk/sabha/:/rails/storage/"
```

**Environment variables**

Copy `.env.sample` to `.kamal/secrets` and fill in your values:

```bash
cp .env.sample .kamal/secrets
```

Add these Kamal-specific variables:

```bash
# Server
SERVER_IP=your.server.ip
PROXY_HOST=chat.yourdomain.com
```

**Generate keys**

```bash
# VAPID keys (web push notifications)
npx web-push generate-vapid-keys

# Secret key base
rails secret

# AnyCable secret
openssl rand -hex 32
```

---

### What's Included

Self-hosting includes everything you need:

- **Thruster** - HTTP/2 proxy with automatic Let's Encrypt SSL
- **SQLite** - Zero-config database (no separate DB server)
- **Redis** - Real-time features (ActionCable)
- **Solid Queue** - Background job processing

### Automatic SSL

Thruster handles SSL certificates automatically via Let's Encrypt. No manual certificate management needed. Just ensure your domain's DNS points to the server.

---

### Backups

Your data lives in `/rails/storage/` (or `/disk/sabha/` with Kamal). Back it up regularly.

**Manual backup**

```bash
# Checkpoint the database first
kamal app exec 'bin/rails runner "ActiveRecord::Base.connection.execute(\"PRAGMA wal_checkpoint(TRUNCATE)\")"'

# Create backup
ssh root@your-server "cd /disk/sabha && tar -czf ~/backup-$(date +%Y%m%d).tar.gz ."

# Download
scp root@your-server:~/backup-*.tar.gz ./backups/
```

**Restore from backup**

```bash
kamal app stop
scp backup.tar.gz root@your-server:/tmp/
ssh root@your-server "cd /disk/sabha && rm -rf * && tar -xzf /tmp/backup.tar.gz"
kamal app boot
```

**Automated backups**

For production, set up a cron job to back up daily to S3, R2, or similar object storage.

---

### Updating

```bash
# Docker Compose
docker compose pull && docker compose up -d

# Kamal
kamal deploy
```

---

### Troubleshooting

**App won't start**

```bash
kamal app logs                    # Check logs
kamal app details                 # Container status
docker logs sabha-web          # Direct Docker logs
```

**Database locked errors**

Stop the old container before deploying:

```bash
kamal app stop
sleep 5
kamal deploy
```

**SSL certificate issues**

```bash
# Check Thruster is receiving traffic on port 80/443
curl -v http://chat.yourdomain.com

# Verify your domain resolves to the server
dig +short chat.yourdomain.com
```

**Out of memory**

Add swap to your server:

```bash
ssh root@your-server "fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile"
```

**Disk space**

```bash
ssh root@your-server "df -h && docker system prune -a -f"
```

---

### Database Maintenance

```bash
# Check WAL mode (should be "wal")
kamal app exec 'bin/rails runner "puts ActiveRecord::Base.connection.execute(\"PRAGMA journal_mode;\").first[\"journal_mode\"]"'

# Optimize database
kamal app exec 'bin/rails runner "ActiveRecord::Base.connection.execute(\"VACUUM\")"'

# Check database size (MB)
kamal app exec 'bin/rails runner "puts ActiveRecord::Base.connection.execute(\"SELECT page_count * page_size / 1024 / 1024.0 as mb FROM pragma_page_count(), pragma_page_size();\").first[\"mb\"]"'
```

---

### Monitoring

**Health check**

```bash
curl -f https://chat.yourdomain.com/up && echo "OK" || echo "FAIL"
```

**Resource usage**

```bash
ssh root@your-server "docker stats --no-stream && df -h && free -h"
```

---

### GitHub Actions CI/CD

Automate deployments on push to main:

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '4.0'

      - name: Install Kamal
        run: gem install kamal

      - name: Setup SSH
        uses: webfactory/ssh-agent@v0.8.0
        with:
          ssh-private-key: ${{ secrets.SSH_KEY }}

      - name: Create secrets
        run: |
          mkdir -p .kamal
          cat > .kamal/secrets <<EOF
          SERVER_IP=${{ secrets.SERVER_IP }}
          PROXY_HOST=${{ secrets.PROXY_HOST }}
          SECRET_KEY_BASE=${{ secrets.SECRET_KEY_BASE }}
          RESEND_API_KEY=${{ secrets.RESEND_API_KEY }}
          VAPID_PUBLIC_KEY=${{ secrets.VAPID_PUBLIC_KEY }}
          VAPID_PRIVATE_KEY=${{ secrets.VAPID_PRIVATE_KEY }}
          APP_NAME=${{ secrets.APP_NAME }}
          APP_HOST=${{ secrets.APP_HOST }}
          COOKIE_DOMAIN=${{ secrets.COOKIE_DOMAIN }}
          SUPPORT_EMAIL=${{ secrets.SUPPORT_EMAIL }}
          MAILER_FROM_NAME=${{ secrets.MAILER_FROM_NAME }}
          MAILER_FROM_EMAIL=${{ secrets.MAILER_FROM_EMAIL }}
          EOF

      - name: Deploy
        run: |
          kamal app stop || true
          sleep 5
          kamal deploy
```

Add secrets to your GitHub repository settings.

---

### Server Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 2 GB | 4 GB |
| CPU | 1 core | 2 cores |
| Disk | 40 GB | 80 GB+ |
| OS | Ubuntu 22.04+ | Ubuntu 24.04 |

---

---

## Sabha Cloud

Don't want to manage servers? [Sabha Cloud](https://cloud.sabha.co) is managed hosting -- we handle servers, updates, security, and backups.

| | Self-Hosting | Sabha Cloud |
|---|---|---|
| Setup time | 30-60 min | 5 min |
| Server management | You | Us |
| Updates | Manual | Automatic |
| Backups | You configure | Automatic |
| Custom domain | Yes | Yes |
| SSL | Automatic | Automatic |
| Data ownership | Full control | You own it |
| Monthly cost | ~$5-20 (server) | [Pricing](https://cloud.sabha.co/pricing) |

Sign up at [cloud.sabha.co](https://cloud.sabha.co).

---

## Questions?

- [GitHub Issues](https://github.com/sabha-co/sabha/issues)
- **Sabha Cloud**: support@cloud.sabha.co
- **Customization**: See [BRANDING.md](./BRANDING.md)
