# Production Deployment Guide

This guide covers production deployment strategies for Campfire-CE. Choose the approach that best fits your needs.

## Table of Contents

- [Deployment Options Overview](#deployment-options-overview)
- [Option 1: Docker Compose (Recommended for Single Server)](#option-1-docker-compose-recommended-for-single-server)
- [Option 2: Kamal (For Multi-Server or Zero-Downtime)](#option-2-kamal-for-multi-server-or-zero-downtime)
- [Common Operations](#common-operations)
- [Monitoring & Maintenance](#monitoring--maintenance)

---

## Deployment Options Overview

### Docker Compose

**Best for:**
- Single server deployments
- Simpler setup and maintenance
- SQLite-based applications
- Small to medium traffic
- Cost-conscious deployments

**Pros:**
- Simple, transparent, standard Docker
- Easy to debug and modify
- Works on any VPS ($5/month+)
- Direct control over everything

**Cons:**
- Brief downtime during updates (~5-10 seconds)
- Manual deployment steps
- Single server only

### Kamal

**Best for:**
- Multi-server deployments
- Zero-downtime requirements
- High-traffic applications
- Teams familiar with deployment tools

**Pros:**
- True zero-downtime rolling deployments
- Multi-server orchestration
- Built-in health checks
- Automated rollbacks

**Cons:**
- More complex setup
- Requires understanding of Kamal concepts
- Can be over-engineered for simple cases

---

## Option 1: Docker Compose (Recommended for Single Server)

> **Database Backups:** Campfire-CE does not include automatic database backups by default. You'll need to implement your own backup strategy. See [Database Backups](#database-backups) section and [LITESTREAM.md](LITESTREAM.md) for options.

### Architecture

```
[Internet] → [Caddy (SSL/Proxy)] → [App Container] → [SQLite on Volume]
                                  ↓
                            [Redis Container]
```

### Prerequisites

1. A VPS/server with Docker installed (Ubuntu 22.04+ recommended)
2. Domain name pointing to your server
3. At least 1GB RAM, 1 CPU core, 10GB disk

### Installation

#### 1. Install Docker

```bash
# On your server
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

#### 2. Setup Deployment Directory

```bash
ssh root@your-server.com
mkdir -p /opt/campfire
cd /opt/campfire
```

#### 3. Create docker-compose.yml

```yaml
version: '3.8'

services:
  web:
    image: ghcr.io/YOUR_USERNAME/campfire-ce:latest
    container_name: campfire-web
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./storage:/rails/storage
    environment:
      RAILS_ENV: production
      REDIS_URL: redis://redis:6379/0
    env_file:
      - .env
    depends_on:
      - redis
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/up"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 40s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  redis:
    image: redis:7-alpine
    container_name: campfire-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  caddy:
    image: caddy:2-alpine
    container_name: campfire-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"  # HTTP/3
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config

volumes:
  redis_data:
  caddy_data:
  caddy_config:
```

#### 4. Create Caddyfile

```
your-domain.com {
    reverse_proxy web:3000

    # Enable compression
    encode gzip

    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000;"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    # Optional: Rate limiting
    # rate_limit {
    #     zone dynamic {
    #         key {remote_host}
    #         events 100
    #         window 1m
    #     }
    # }
}
```

#### 5. Create .env File

```bash
# Generate secret key base
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Create .env file
cat > .env <<EOF
SECRET_KEY_BASE=$SECRET_KEY_BASE
RAILS_ENV=production

# App Configuration
APP_NAME=Campfire
APP_SHORT_NAME=Campfire
APP_DESCRIPTION=Your community chat
APP_HOST=your-domain.com
COOKIE_DOMAIN=your-domain.com

# Email Configuration
SUPPORT_EMAIL=support@your-domain.com
MAILER_FROM_NAME=Campfire
MAILER_FROM_EMAIL=noreply@your-domain.com
RESEND_API_KEY=your_resend_api_key

# Storage (AWS S3)
AWS_ACCESS_KEY_ID=your_aws_key
AWS_SECRET_ACCESS_KEY=your_aws_secret
AWS_DEFAULT_REGION=us-east-1

# Web Push Notifications (generate with: rails secret)
VAPID_PUBLIC_KEY=your_vapid_public_key
VAPID_PRIVATE_KEY=your_vapid_private_key

# Optional: Gumroad Integration
GUMROAD_ON=false
# GUMROAD_ACCESS_TOKEN=
# GUMROAD_PRODUCT_IDS=

# Optional: Vimeo Integration
# VIMEO_ACCESS_TOKEN=

# Optional: Analytics
# ANALYTICS_DOMAIN=

# Webhook Secret (generate with: openssl rand -hex 32)
WEBHOOK_SECRET=$(openssl rand -hex 32)

# Theme
THEME_COLOR=#3b82f6
BACKGROUND_COLOR=#ffffff

# CSP Frame Ancestors (optional)
# CSP_FRAME_ANCESTORS=https://trusted-site.com

# Deployment metadata
APP_VERSION=$(git rev-parse --short HEAD || echo "unknown")
LAST_DEPLOY=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

# Secure the file
chmod 600 .env
```

#### 6. Initial Deployment

```bash
# Pull and start all services
docker-compose up -d

# Watch logs
docker-compose logs -f

# Run initial database setup
docker-compose exec web bin/rails db:prepare

# Verify
docker-compose ps
curl https://your-domain.com
```

### Deployment Updates

#### Simple Deploy Script (with ~5s downtime)

Create `/opt/campfire/deploy.sh`:

```bash
#!/bin/bash
set -e

echo "🚀 Deploying Campfire-CE..."

cd /opt/campfire

# Pull new image
echo "📥 Pulling latest image..."
docker-compose pull web

# Stop old container
echo "🛑 Stopping old container..."
docker-compose stop web

# Start new container
echo "✅ Starting new container..."
docker-compose up -d web

# Run migrations if needed
echo "🗄️  Running migrations..."
docker-compose exec -T web bin/rails db:migrate

# Health check
echo "🏥 Waiting for health check..."
sleep 10
if curl -f http://localhost:3000/up > /dev/null 2>&1; then
    echo "✅ Deployment successful!"
else
    echo "❌ Health check failed!"
    docker-compose logs --tail=50 web
    exit 1
fi

# Show logs
docker-compose logs --tail=30 web
```

```bash
chmod +x deploy.sh
```

#### Build and Deploy

```bash
# On your local machine - build and push
docker build -t ghcr.io/YOUR_USERNAME/campfire-ce:latest .
docker push ghcr.io/YOUR_USERNAME/campfire-ce:latest

# On your server - deploy
./deploy.sh
```

### GitHub Actions Auto-Deploy

Create `.github/workflows/deploy-docker.yml`:

```yaml
name: Build and Deploy (Docker)

on:
  push:
    branches: [main, master]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.sha }}

      - name: Deploy to server
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_KEY }}
          script: |
            cd /opt/campfire
            docker-compose pull web
            docker-compose stop web
            docker-compose up -d web
            docker-compose exec -T web bin/rails db:migrate
```

Add these secrets to your GitHub repository:
- `SSH_HOST`: Your server IP/domain
- `SSH_USER`: SSH username (usually `root`)
- `SSH_KEY`: Private SSH key

---

## Option 2: Kamal (For Multi-Server or Zero-Downtime)

> **Note on Database Backups:** Campfire-CE does not include automatic database backups by default, regardless of deployment method. You'll need to set up your own backup solution (see [Database Backups](#database-backups) section below).

### Prerequisites

1. Server(s) with Docker installed
2. Domain name with SSL
3. Kamal installed locally: `gem install kamal`

### Configuration

The repository already has `config/deploy.yml` configured. Key settings:

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

### Environment Setup

Create `.kamal/secrets`:

```bash
# Copy from .env.sample
cp .env.sample .kamal/secrets

# Edit with your values
nano .kamal/secrets

# Required variables:
# SERVER_IP=143.244.132.154
# PROXY_HOST=your-domain.com
# SECRET_KEY_BASE=...
# (all other environment variables)
```

### Deployment Commands

```bash
# Initial setup (first time only)
kamal setup

# Regular deployments
kamal deploy

# Check status
kamal app containers
kamal app logs

# Rails console
kamal app exec 'bin/rails console'

# Database console
kamal app exec 'bin/rails dbconsole'

# Stop application
kamal app stop

# Remove everything
kamal app remove
```

### Known Issues with SQLite + Kamal

**Problem:** Kamal's rolling deployments can cause SQLite lock issues even with WAL mode enabled, because:
1. New container starts while old container is still running
2. Both try to access the same SQLite file
3. New container's `db:prepare` may wait for locks
4. Health checks timeout before Rails server starts

**Workarounds:**

1. **Use Simple Deployment** (brief downtime acceptable):
   ```bash
   # Stop old container first
   kamal app stop

   # Then deploy
   kamal deploy
   ```

2. **Increase Timeouts** (add to `config/deploy.yml`):
   ```yaml
   proxy:
     ssl: true
     host: <%= ENV.fetch("PROXY_HOST") %>
     app_port: 3000
     deploy_timeout: 180
     readiness_delay: 30
   ```

3. **Consider PostgreSQL** for production if you need true zero-downtime with Kamal

### GitHub Actions with Kamal

Create `.github/workflows/deploy-kamal.yml`:

```yaml
name: Deploy with Kamal

on:
  push:
    branches: [main, master]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Install Kamal
        run: gem install kamal

      - name: Setup SSH
        uses: webfactory/ssh-agent@v0.8.0
        with:
          ssh-private-key: ${{ secrets.SSH_KEY }}

      - name: Create secrets file
        run: |
          mkdir -p .kamal
          cat > .kamal/secrets <<EOF
          SERVER_IP=${{ secrets.SERVER_IP }}
          PROXY_HOST=${{ secrets.PROXY_HOST }}
          SECRET_KEY_BASE=${{ secrets.SECRET_KEY_BASE }}
          # Add all other secrets...
          EOF

      - name: Deploy
        run: |
          # Stop old container to avoid SQLite locks
          kamal app stop || true
          sleep 5
          # Deploy new version
          kamal deploy
```

---

## Common Operations

### Database Backups

#### Automated Backup Script

Create `/opt/campfire/backup.sh` (works with both Docker Compose and Kamal):

```bash
#!/bin/bash
set -e

BACKUP_DIR="/opt/campfire/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/campfire_backup_$DATE.tar.gz"

mkdir -p $BACKUP_DIR

echo "Creating backup: $BACKUP_FILE"

# For Docker Compose
if command -v docker-compose &> /dev/null; then
    # Checkpoint WAL file first
    docker-compose exec -T web bin/rails runner \
        "ActiveRecord::Base.connection.execute('PRAGMA wal_checkpoint(TRUNCATE)')" || true

    # Create backup
    tar -czf $BACKUP_FILE ./storage/
fi

# For Kamal
if command -v kamal &> /dev/null; then
    # Checkpoint WAL file first
    kamal app exec 'bin/rails runner "ActiveRecord::Base.connection.execute(\"PRAGMA wal_checkpoint(TRUNCATE)\")"' || true

    # Create backup from server
    ssh root@$SERVER_IP "cd /disk/campfire && tar -czf /tmp/backup.tar.gz ."
    scp root@$SERVER_IP:/tmp/backup.tar.gz $BACKUP_FILE
    ssh root@$SERVER_IP "rm /tmp/backup.tar.gz"
fi

# Upload to S3 (optional)
if command -v aws &> /dev/null && [ ! -z "$AWS_BUCKET" ]; then
    aws s3 cp $BACKUP_FILE s3://$AWS_BUCKET/backups/
    echo "Uploaded to S3"
fi

# Keep only last 7 days
find $BACKUP_DIR -name "campfire_backup_*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
ls -lh $BACKUP_FILE
```

```bash
chmod +x /opt/campfire/backup.sh

# Add to crontab for daily backups at 2 AM
crontab -e
# Add: 0 2 * * * /opt/campfire/backup.sh >> /opt/campfire/backup.log 2>&1
```

#### Manual Backup

```bash
# Docker Compose
cd /opt/campfire
docker-compose exec web bin/rails runner \
    "ActiveRecord::Base.connection.execute('PRAGMA wal_checkpoint(TRUNCATE)')"
tar -czf backup-$(date +%Y%m%d).tar.gz ./storage/

# Kamal
kamal app exec 'bin/rails runner "ActiveRecord::Base.connection.execute(\"PRAGMA wal_checkpoint(TRUNCATE)\")"'
ssh root@$SERVER_IP "cd /disk/campfire && tar -czf ~/backup-$(date +%Y%m%d).tar.gz ."
```

#### Restore from Backup

```bash
# Docker Compose
cd /opt/campfire
docker-compose stop web
tar -xzf backup-20231201.tar.gz
docker-compose up -d web

# Kamal
kamal app stop
ssh root@$SERVER_IP "cd /disk/campfire && tar -xzf ~/backup-20231201.tar.gz"
kamal app boot
```

### Rails Console Access

```bash
# Docker Compose
docker-compose exec web bin/rails console

# Kamal
kamal app exec --interactive --reuse 'bin/rails console'
# Or use alias
kamal console
```

### View Logs

```bash
# Docker Compose
docker-compose logs -f web              # Follow logs
docker-compose logs --tail=100 web      # Last 100 lines
docker-compose logs --since=1h web      # Last hour

# Kamal
kamal app logs                          # Recent logs
kamal app logs -f                       # Follow logs
kamal logs                              # Use alias
```

### Database Console

```bash
# Docker Compose
docker-compose exec web bin/rails dbconsole

# Kamal
kamal app exec --interactive --reuse 'bin/rails dbconsole'
# Or use alias
kamal dbc
```

### Run Migrations

```bash
# Docker Compose
docker-compose exec web bin/rails db:migrate

# Kamal
kamal app exec 'bin/rails db:migrate'
```

### Check Application Health

```bash
# Docker Compose
docker-compose ps
curl http://localhost:3000/up

# Kamal
kamal app containers
kamal app details
```

---

## Monitoring & Maintenance

### Health Monitoring

Both deployments expose `/up` endpoint for health checks:

```bash
curl https://your-domain.com/up
```

### Resource Monitoring

```bash
# Docker stats
docker stats

# Disk usage
df -h
du -sh /opt/campfire/storage/

# Memory usage
free -h
```

### Log Rotation

Both approaches automatically rotate logs:

**Docker Compose**: Configured in docker-compose.yml
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

**Kamal**: Configured in deploy.yml
```yaml
logging:
  options:
    max-size: "10m"
```

### Database Maintenance

```bash
# Check WAL mode (should be "wal")
docker-compose exec web sqlite3 storage/db/production.sqlite3 "PRAGMA journal_mode;"

# Optimize database
docker-compose exec web bin/rails runner \
    "ActiveRecord::Base.connection.execute('VACUUM')"

# Check database size
docker-compose exec web bin/rails runner \
    "puts ActiveRecord::Base.connection.execute('SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size();').first['size'] / 1024 / 1024.0"
```

### Security Updates

```bash
# Update base images
docker-compose pull
docker-compose up -d

# Update system packages (on server)
apt update && apt upgrade -y
```

### SSL Certificate Renewal

With Caddy, SSL certificates auto-renew. To force renewal:

```bash
docker-compose exec caddy caddy reload
```

---

## Troubleshooting

### Application Won't Start

```bash
# Check logs
docker-compose logs web
kamal app logs

# Try starting in foreground
docker-compose up web

# Check health
docker-compose ps
kamal app details
```

### Database Locked Errors

```bash
# Check WAL mode
docker-compose exec web sqlite3 storage/db/production.sqlite3 "PRAGMA journal_mode;"

# Should return: wal

# Checkpoint WAL file
docker-compose exec web bin/rails runner \
    "ActiveRecord::Base.connection.execute('PRAGMA wal_checkpoint(TRUNCATE)')"

# For Kamal: stop old container before deploying
kamal app stop
kamal deploy
```

### Out of Memory

```bash
# Check memory usage
free -h
docker stats

# Add swap if needed
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### Disk Space Issues

```bash
# Check disk usage
df -h
du -sh /opt/campfire/storage/

# Clean old Docker images
docker system prune -a

# Clean old backups
find /opt/campfire/backups -name "*.tar.gz" -mtime +30 -delete
```

### Port Already in Use

```bash
# Find process using port 3000
lsof -i :3000
netstat -tulpn | grep 3000

# Kill process
kill -9 <PID>
```

### Reset Everything

```bash
# Docker Compose
docker-compose down -v
rm -rf storage/
docker-compose up -d
docker-compose exec web bin/rails db:setup

# Kamal
kamal app remove
kamal setup
```

---

## Performance Optimization

### Database Optimizations

Already configured in `config/initializers/sqlite3.rb`:

```ruby
# Busy timeout for retries
db_config.timeout = 5000

# Immediate transaction mode
db_config.default_transaction_mode = :immediate

# Custom busy handler
conn.busy_handler do |count|
  sleep(0.01 * count)
  count < 100
end
```

### Caching

Configure Redis caching in `config/environments/production.rb`:

```ruby
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
```

### Asset CDN

Consider using a CDN for static assets:

```ruby
# config/environments/production.rb
config.asset_host = 'https://cdn.your-domain.com'
```

---

## Comparison Summary

| Feature | Docker Compose | Kamal |
|---------|---------------|-------|
| Setup Complexity | ⭐⭐ Simple | ⭐⭐⭐⭐ Complex |
| Deployment Speed | Fast (1-2 min) | Medium (2-5 min) |
| Downtime | ~5 seconds | 0 seconds |
| SQLite Compatibility | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐ Good (with caveats) |
| Multi-Server | ❌ No | ✅ Yes |
| Learning Curve | ⭐⭐ Easy | ⭐⭐⭐⭐ Steep |
| Debugging | ⭐⭐⭐⭐⭐ Transparent | ⭐⭐⭐ Abstract |
| Cost | $5/month | $5-50/month |
| Best For | Single server, SQLite | Multi-server, PostgreSQL |

## Recommendations

- **For most users**: Start with **Docker Compose**. It's simpler, more transparent, and works perfectly with SQLite.

- **Upgrade to Kamal** only if you:
  - Need true zero-downtime deployments
  - Have multiple servers
  - Switch to PostgreSQL/MySQL
  - Have complex deployment requirements

- **For Production**: Both are production-ready. Docker Compose is actually more reliable for SQLite-based apps.

---

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Kamal Documentation](https://kamal-deploy.org/)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [SQLite in Production](https://joyofrails.com/articles/what-you-need-to-know-about-sqlite)
