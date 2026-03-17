# Deploying Sabha

Deploy Sabha on your own server. Full control, own your data, server costs only (~$5-20/month).

For multi-tenant SaaS deployment, see [multi-tenant/DEPLOYMENT.md](./multi-tenant/DEPLOYMENT.md).

---

## Deploying with Kamal (Recommended)

[Kamal](https://kamal-deploy.org/) gives you zero-downtime Docker deployments with AnyCable support for high-performance WebSockets.

### Requirements

- A VPS with 2GB+ RAM (DigitalOcean, Hetzner, Linode, etc.)
- A domain name pointing to your server
- Docker installed locally
- Kamal installed locally (`gem install kamal`)

### Setup

```bash
# Prepare your server
ssh root@your-server "curl -fsSL https://get.docker.com | sh && mkdir -p /disk/sabha"

# Clone the repo
git clone https://github.com/sabha-co/sabha.git
cd sabha

# Configure secrets
cp .env.sample .kamal/secrets
nano .kamal/secrets  # Add SERVER_IP, PROXY_HOST, and other vars

# Deploy
kamal setup
```

### Common commands

```bash
kamal deploy              # Deploy updates
kamal app logs -f         # Follow logs
kamal app exec 'bin/rails console'  # Rails console
kamal app stop            # Stop app
kamal app boot            # Start app
```

### Kamal configuration

The repo includes `config/deploy.yml`:

```yaml
service: sabha
image: sabha-co/sabha

servers:
  web:
    hosts:
      - <%= ENV.fetch("SERVER_IP") %>
    options:
      network-alias: sabha-web

proxy:
  ssl: true
  host: <%= ENV.fetch("PROXY_HOST") %>
  app_port: 3000

volumes:
  - "/disk/sabha/:/rails/storage/"

# AnyCable — kamal-proxy routes /cable to AnyCable-Go
accessories:
  anycable:
    image: anycable/anycable-go:1.6
    host: <%= ENV.fetch("SERVER_IP") %>
    proxy:
      host: <%= ENV.fetch("PROXY_HOST") %>
      app_port: 8080
      path_prefix: /cable
    env:
      clear:
        ANYCABLE_HOST: "0.0.0.0"
        ANYCABLE_PORT: "8080"
        ANYCABLE_RPC_HOST: "http://sabha-web:3000/_anycable"
        ANYCABLE_BROADCAST_ADAPTER: "http"
      secret:
        - ANYCABLE_SECRET
```

---

## Docker Compose (Alternative)

For a simpler setup without Kamal. Uses pre-built Docker images — no need to clone the repo.

### Requirements

- A VPS with 2GB+ RAM
- A domain name pointing to your server
- Docker installed on the server

### 1. Install Docker on your server

```bash
curl -fsSL https://get.docker.com | sh
```

### 2. Create a project directory and `docker-compose.yml`

```bash
mkdir -p ~/sabha && cd ~/sabha
```

```yaml
services:
  web:
    image: ghcr.io/sabha-co/sabha:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    env_file: .env
    volumes:
      - sabha_storage:/rails/storage

volumes:
  sabha_storage:
```

### 3. Configure environment

Create a `.env` file with your settings:

```bash
# Domain
APP_HOST=chat.yourdomain.com

# SSL (required for automatic Let's Encrypt certificate)
TLS_DOMAIN=chat.yourdomain.com

# Security (generate with: openssl rand -hex 64)
SECRET_KEY_BASE=your_secret_key_here

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

# WebSockets (uses ActionCable through Puma)
ANYCABLE_ENABLED=false

# Authentication: "password" (default) or "otp"
AUTH_METHOD=password

# Cookie domain
COOKIE_DOMAIN=chat.yourdomain.com
```

### 4. Start

```bash
docker compose up -d
```

Your community is live at `https://chat.yourdomain.com`

---

## What's Included

The Docker image includes everything you need:

- **Thruster** — HTTP/2 proxy with automatic Let's Encrypt SSL
- **SQLite** — zero-config database (no separate DB server)
- **Redis** — real-time features (ActionCable pub/sub + cache)
- **Solid Queue** — background job processing

Thruster handles SSL certificates automatically via Let's Encrypt. Just ensure your domain's DNS points to the server.

**Cloudflare users:** Set your DNS record to **DNS only** (grey cloud, not proxied). Cloudflare's proxy intercepts the Let's Encrypt ACME challenge, preventing Thruster from provisioning its certificate.

**AnyCable:** The Docker Compose setup uses ActionCable (WebSockets through Puma) by default. AnyCable requires a reverse proxy to route `/cable` traffic — the Kamal deployment handles this with kamal-proxy.

---

## Updating

**Kamal:**

```bash
kamal deploy
```

**Docker Compose:**

```bash
docker compose pull && docker compose up -d
```

---

## Backups

Your data lives in a Docker volume mounted at `/rails/storage` inside the container. Back it up regularly.

**Manual backup**

```bash
# Checkpoint the database
docker compose exec web bin/rails runner "ActiveRecord::Base.connection.execute('PRAGMA wal_checkpoint(TRUNCATE)')"

# Find volume path and back up
VOLUME=$(docker volume ls -q | grep sabha_storage | head -1)
tar -czf ~/sabha-backup-$(date +%Y%m%d).tar.gz -C $(docker volume inspect $VOLUME --format '{{ .Mountpoint }}') .
```

**Restore from backup**

```bash
docker compose down
VOLUME=$(docker volume ls -q | grep sabha_storage | head -1)
tar -xzf sabha-backup.tar.gz -C $(docker volume inspect $VOLUME --format '{{ .Mountpoint }}')
docker compose up -d
```

For production, set up a cron job to back up daily to S3, R2, or similar object storage.

---

## Monitoring

**Health check**

```bash
curl -f https://chat.yourdomain.com/up && echo "OK" || echo "FAIL"
```

**Resource usage**

```bash
ssh root@your-server "docker stats --no-stream && df -h && free -h"
```

---

## Database Maintenance

```bash
# Check WAL mode (should be "wal")
docker compose exec web bin/rails runner "puts ActiveRecord::Base.connection.execute('PRAGMA journal_mode;').first['journal_mode']"

# Optimize database
docker compose exec web bin/rails runner "ActiveRecord::Base.connection.execute('VACUUM')"

# Check database size (MB)
docker compose exec web bin/rails runner "puts ActiveRecord::Base.connection.execute('SELECT page_count * page_size / 1024 / 1024.0 as mb FROM pragma_page_count(), pragma_page_size();').first['mb']"
```

---

## Server Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 2 GB | 4 GB |
| CPU | 1 core | 2 cores |
| Disk | 40 GB | 80 GB+ |
| OS | Ubuntu 22.04+ | Ubuntu 24.04 |
