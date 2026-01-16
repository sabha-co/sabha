# Deploying Campfire-CE

Two ways to run your community:

1. **Self-hosting** - Run on your own server with full control
2. **Campfire Cloud** - Managed hosting, we handle everything

---

## Self-Hosting

Deploy Campfire-CE on your own VPS. You get full control, own your data, and pay only for server costs (~$5-20/month).

### Requirements

- A VPS with 1GB+ RAM (DigitalOcean, Hetzner, Linode, etc.)
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
git clone https://github.com/superforumio/campfire-ce.git
cd campfire-ce
cp .env.sample .env
nano .env
```

**4. Set your environment variables**

```bash
# Domain (required for automatic SSL)
APP_HOST=chat.yourdomain.com
TLS_DOMAIN=chat.yourdomain.com

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

# Web Push (generate with: bundle exec rails runner "require 'webpush'; k = Webpush.generate_key; puts k.public_key; puts k.private_key")
VAPID_PUBLIC_KEY=your_public_key
VAPID_PRIVATE_KEY=your_private_key
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
ssh root@your-server "curl -fsSL https://get.docker.com | sh && mkdir -p /disk/campfire"

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
service: campfire
image: campfire-ce

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
  - "/disk/campfire/:/rails/storage/"
```

**Environment variables**

Add these to `.kamal/secrets`:

```bash
# Server
SERVER_IP=your.server.ip
PROXY_HOST=chat.yourdomain.com

# Rails
SECRET_KEY_BASE=$(openssl rand -hex 64)
RAILS_ENV=production

# App
APP_NAME=My Community
APP_SHORT_NAME=Community
APP_DESCRIPTION=Your community chat
APP_HOST=chat.yourdomain.com
COOKIE_DOMAIN=chat.yourdomain.com

# Email (get key from resend.com)
RESEND_API_KEY=your_key
SUPPORT_EMAIL=support@yourdomain.com
MAILER_FROM_NAME=My Community
MAILER_FROM_EMAIL=noreply@yourdomain.com

# Web Push (see "Generate VAPID Keys" below)
VAPID_PUBLIC_KEY=your_public_key
VAPID_PRIVATE_KEY=your_private_key

# Webhook
WEBHOOK_SECRET=$(openssl rand -hex 32)
```

**Generate VAPID keys**

```bash
bundle exec rails runner "require 'webpush'; k = Webpush.generate_key; puts 'VAPID_PUBLIC_KEY=' + k.public_key; puts 'VAPID_PRIVATE_KEY=' + k.private_key"
```

---

### What's Included

Self-hosting includes everything you need:

- **Thruster** - HTTP/2 proxy with automatic Let's Encrypt SSL
- **SQLite** - Zero-config database (no separate DB server)
- **Redis** - Real-time features (ActionCable)
- **Solid Queue** - Background job processing

### Automatic SSL

Set `TLS_DOMAIN` and Thruster handles SSL certificates automatically:

```bash
TLS_DOMAIN=chat.yourdomain.com
```

No manual certificate management needed.

---

### Backups

Your data lives in `/rails/storage/` (or `/disk/campfire/` with Kamal). Back it up regularly.

**Manual backup**

```bash
# Checkpoint the database first
kamal app exec 'bin/rails runner "ActiveRecord::Base.connection.execute(\"PRAGMA wal_checkpoint(TRUNCATE)\")"'

# Create backup
ssh root@your-server "cd /disk/campfire && tar -czf ~/backup-$(date +%Y%m%d).tar.gz ."

# Download
scp root@your-server:~/backup-*.tar.gz ./backups/
```

**Restore from backup**

```bash
kamal app stop
scp backup.tar.gz root@your-server:/tmp/
ssh root@your-server "cd /disk/campfire && rm -rf * && tar -xzf /tmp/backup.tar.gz"
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
docker logs campfire-web          # Direct Docker logs
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

# Verify TLS_DOMAIN is set
kamal envify | grep TLS_DOMAIN
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
          ruby-version: '3.3'

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
| RAM | 1 GB | 2 GB |
| CPU | 1 core | 2 cores |
| Disk | 10 GB | 20 GB+ |
| OS | Ubuntu 22.04+ | Ubuntu 24.04 |

---

## Campfire Cloud

Don't want to manage servers? [Campfire Cloud](https://campfirecloud.com) handles everything.

### What You Get

- **Instant setup** - Live in minutes, not hours
- **Managed hosting** - We handle servers, updates, security
- **Automatic backups** - Continuous backup to cloud storage
- **Custom domains** - Your domain with automatic SSL
- **Zero maintenance** - No servers to manage, ever

### Getting Started

1. Sign up at [campfirecloud.com](https://campfirecloud.com)
2. Choose your subdomain (e.g., `mycommunity.campfirecloud.com`)
3. Optionally connect a custom domain
4. Invite your community

### Custom Domains

1. Go to Settings > Custom Domain
2. Enter your domain (e.g., `chat.yourdomain.com`)
3. Add the DNS records we provide
4. SSL is provisioned automatically

### When to Choose Campfire Cloud

- You want to focus on community, not infrastructure
- You don't have technical staff
- You need guaranteed uptime and support
- You want automatic updates and security patches

---

## Comparison

| Feature | Self-Hosting | Campfire Cloud |
|---------|--------------|----------------|
| Setup time | 30-60 min | 5 min |
| Server management | You | Us |
| Updates | Manual | Automatic |
| Backups | You configure | Automatic |
| Custom domain | Yes | Yes |
| SSL | Automatic | Automatic |
| Data ownership | Full control | You own it |
| Monthly cost | ~$5-20 | [Pricing](https://campfirecloud.com/pricing) |

---

## Questions?

- **Self-hosting**: [GitHub Issues](https://github.com/superforumio/campfire-ce/issues)
- **Campfire Cloud**: ashwin@campfirecloud.com
- **Customization**: See [BRANDING.md](../BRANDING.md)
