# Production Deployment Guide

This guide covers deploying Campfire-CE to production using **Kamal**.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Deployment Commands](#deployment-commands)
- [Common Operations](#common-operations)
- [Database Backups](#database-backups)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

1. A VPS/server with Docker installed (Ubuntu 22.04+ recommended)
2. Domain name pointing to your server
3. At least 1GB RAM, 1 CPU core, 10GB disk
4. Kamal installed locally: `gem install kamal`
5. SSH access to your server

### Server Preparation

```bash
# On your server
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Create storage directory
mkdir -p /disk/campfire
```

---

## Configuration

### 1. Kamal Configuration

The repository includes `config/deploy.yml` with default settings:

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

### 2. Environment Setup

Create `.kamal/secrets` with your configuration:

```bash
# Copy from sample
cp .env.sample .kamal/secrets

# Edit with your values
nano .kamal/secrets
```

**Required variables:**

```bash
# Server
SERVER_IP=your.server.ip
PROXY_HOST=your-domain.com

# Rails
SECRET_KEY_BASE=$(openssl rand -hex 64)
RAILS_ENV=production

# App Configuration
APP_NAME=Campfire
APP_SHORT_NAME=Campfire
APP_DESCRIPTION=Your community chat
APP_HOST=your-domain.com
COOKIE_DOMAIN=your-domain.com

# Email (Resend)
SUPPORT_EMAIL=support@your-domain.com
MAILER_FROM_NAME=Campfire
MAILER_FROM_EMAIL=noreply@your-domain.com
RESEND_API_KEY=your_resend_api_key

# Web Push Notifications
VAPID_PUBLIC_KEY=your_vapid_public_key
VAPID_PRIVATE_KEY=your_vapid_private_key

# Webhook Secret
WEBHOOK_SECRET=$(openssl rand -hex 32)

# Theme
THEME_COLOR=#3b82f6
BACKGROUND_COLOR=#ffffff
```

**Optional variables:**

```bash
# Storage (AWS S3) - for file attachments
AWS_ACCESS_KEY_ID=your_aws_key
AWS_SECRET_ACCESS_KEY=your_aws_secret
AWS_DEFAULT_REGION=us-east-1

# Gumroad Integration
GUMROAD_ON=false
# GUMROAD_ACCESS_TOKEN=
# GUMROAD_PRODUCT_IDS=

# Analytics
# ANALYTICS_DOMAIN=

# CSP Frame Ancestors
# CSP_FRAME_ANCESTORS=https://trusted-site.com
```

### Generate VAPID Keys

```bash
# In Rails console
bundle exec rails runner "
  require 'webpush'
  vapid_key = Webpush.generate_key
  puts 'VAPID_PUBLIC_KEY=' + vapid_key.public_key
  puts 'VAPID_PRIVATE_KEY=' + vapid_key.private_key
"
```

---

## Deployment Commands

### Initial Setup

```bash
# First-time deployment (sets up server, registry, deploys app)
kamal setup
```

### Regular Deployments

```bash
# Deploy latest changes
kamal deploy

# Deploy with verbose output
kamal deploy -v
```

### Status & Logs

```bash
# Check container status
kamal app containers

# View application details
kamal app details

# View logs
kamal app logs
kamal app logs -f  # Follow logs
```

### Rails Console & Database

```bash
# Rails console
kamal app exec 'bin/rails console'

# Database console
kamal app exec 'bin/rails dbconsole'

# Run migrations
kamal app exec 'bin/rails db:migrate'

# Run a specific task
kamal app exec 'bin/rails some:task'
```

### Application Control

```bash
# Stop application
kamal app stop

# Start application
kamal app boot

# Restart application
kamal app boot --restart

# Remove everything (dangerous!)
kamal app remove
```

---

## Common Operations

### View Environment Variables

```bash
kamal envify
```

### SSH to Server

```bash
kamal app exec -i bash
```

### Check Health

```bash
curl https://your-domain.com/up
```

---

## Database Backups

> **Important:** Campfire-CE uses SQLite. You must implement your own backup strategy.

### Manual Backup

```bash
# Checkpoint WAL file first
kamal app exec 'bin/rails runner "ActiveRecord::Base.connection.execute(\"PRAGMA wal_checkpoint(TRUNCATE)\")"'

# Create backup on server
ssh root@$SERVER_IP "cd /disk/campfire && tar -czf ~/backup-$(date +%Y%m%d).tar.gz ."

# Download backup
scp root@$SERVER_IP:~/backup-*.tar.gz ./backups/
```

### Automated Backup Script

Create `backup.sh` on your local machine:

```bash
#!/bin/bash
set -e

SERVER_IP="${SERVER_IP:-your.server.ip}"
BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

echo "Checkpointing WAL..."
kamal app exec 'bin/rails runner "ActiveRecord::Base.connection.execute(\"PRAGMA wal_checkpoint(TRUNCATE)\")"' || true

echo "Creating backup..."
ssh root@$SERVER_IP "cd /disk/campfire && tar -czf /tmp/backup.tar.gz ."
scp root@$SERVER_IP:/tmp/backup.tar.gz "$BACKUP_DIR/campfire_backup_$DATE.tar.gz"
ssh root@$SERVER_IP "rm /tmp/backup.tar.gz"

# Optional: Upload to S3
# aws s3 cp "$BACKUP_DIR/campfire_backup_$DATE.tar.gz" s3://your-bucket/backups/

# Keep only last 7 backups
ls -t $BACKUP_DIR/campfire_backup_*.tar.gz | tail -n +8 | xargs -r rm

echo "Backup completed: $BACKUP_DIR/campfire_backup_$DATE.tar.gz"
```

### Restore from Backup

```bash
# Stop application
kamal app stop

# Upload and extract backup
scp backup-20231201.tar.gz root@$SERVER_IP:/tmp/
ssh root@$SERVER_IP "cd /disk/campfire && rm -rf * && tar -xzf /tmp/backup-20231201.tar.gz"

# Start application
kamal app boot
```

---

## Monitoring & Maintenance

### Health Monitoring

The `/up` endpoint returns 200 when healthy:

```bash
curl -f https://your-domain.com/up && echo "OK" || echo "FAIL"
```

### Resource Monitoring

```bash
# On server
docker stats
df -h
free -h
du -sh /disk/campfire/
```

### Database Maintenance

```bash
# Check WAL mode
kamal app exec 'bin/rails runner "puts ActiveRecord::Base.connection.execute(\"PRAGMA journal_mode;\").first[\"journal_mode\"]"'

# Optimize database
kamal app exec 'bin/rails runner "ActiveRecord::Base.connection.execute(\"VACUUM\")"'

# Check database size (MB)
kamal app exec 'bin/rails runner "puts ActiveRecord::Base.connection.execute(\"SELECT page_count * page_size / 1024 / 1024.0 as mb FROM pragma_page_count(), pragma_page_size();\").first[\"mb\"]"'
```

### Log Rotation

Kamal configures log rotation automatically. You can customize in `config/deploy.yml`:

```yaml
logging:
  options:
    max-size: "10m"
    max-file: "3"
```

---

## Troubleshooting

### Application Won't Start

```bash
# Check logs
kamal app logs

# Check container status
kamal app details

# Try starting manually
kamal app boot -v
```

### Database Locked Errors

SQLite lock issues during deployment:

```bash
# Stop old container before deploying
kamal app stop
sleep 5
kamal deploy
```

Or add timeouts to `config/deploy.yml`:

```yaml
proxy:
  ssl: true
  host: <%= ENV.fetch("PROXY_HOST") %>
  app_port: 3000
  deploy_timeout: 180
  readiness_delay: 30
```

### Out of Memory

```bash
# Check memory on server
ssh root@$SERVER_IP "free -h && docker stats --no-stream"

# Add swap if needed
ssh root@$SERVER_IP "
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
"
```

### Disk Space Issues

```bash
# Check disk usage
ssh root@$SERVER_IP "df -h && du -sh /disk/campfire/"

# Clean old Docker images
ssh root@$SERVER_IP "docker system prune -a -f"
```

### SSL Certificate Issues

Kamal proxy handles SSL automatically via Let's Encrypt. If certificates fail:

```bash
# Check proxy logs
kamal proxy logs

# Restart proxy
kamal proxy reboot
```

### Reset Everything

```bash
# Remove all containers and data (DANGEROUS!)
kamal app remove

# Clean server storage
ssh root@$SERVER_IP "rm -rf /disk/campfire/*"

# Fresh setup
kamal setup
```

---

## GitHub Actions CI/CD

Create `.github/workflows/deploy.yml`:

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
          RESEND_API_KEY=${{ secrets.RESEND_API_KEY }}
          VAPID_PUBLIC_KEY=${{ secrets.VAPID_PUBLIC_KEY }}
          VAPID_PRIVATE_KEY=${{ secrets.VAPID_PRIVATE_KEY }}
          WEBHOOK_SECRET=${{ secrets.WEBHOOK_SECRET }}
          APP_NAME=${{ secrets.APP_NAME }}
          APP_HOST=${{ secrets.APP_HOST }}
          COOKIE_DOMAIN=${{ secrets.COOKIE_DOMAIN }}
          SUPPORT_EMAIL=${{ secrets.SUPPORT_EMAIL }}
          MAILER_FROM_NAME=${{ secrets.MAILER_FROM_NAME }}
          MAILER_FROM_EMAIL=${{ secrets.MAILER_FROM_EMAIL }}
          EOF

      - name: Deploy
        run: |
          # Stop old container to avoid SQLite locks
          kamal app stop || true
          sleep 5
          kamal deploy
```

Add these secrets to your GitHub repository settings.

---

## Additional Resources

- [Kamal Documentation](https://kamal-deploy.org/)
- [SQLite in Production](https://www.sqlite.org/whentouse.html)
