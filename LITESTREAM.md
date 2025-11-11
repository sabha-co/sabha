# Litestream Database Backup Guide

> **IMPORTANT:** This guide describes how to set up Litestream for SQLite database backups. **Litestream is NOT currently included or configured in this repository.** This document serves as a reference for implementing your own backup solution.

## Current State

Campfire-CE **does not** ship with Litestream integration. Users must implement their own database backup strategy. This guide provides instructions for adding Litestream if you choose to use it.

## What is Litestream?

Litestream is a standalone streaming replication tool for SQLite databases that:
- Continuously replicates changes to S3-compatible storage
- Provides point-in-time recovery
- Runs as a separate process alongside your application
- Works with any S3-compatible storage (AWS S3, Cloudflare R2, etc.)

## Why This Guide Exists

This guide helps users who want to add Litestream backups to their Campfire-CE deployment. It covers:
- How to configure Litestream for Campfire-CE's SQLite database
- Environment variables needed
- Deployment patterns (docker-compose sidecar or standalone)
- Restoration procedures

## Implementation Options

### Option 1: Docker Compose Sidecar (Recommended)

Add a Litestream sidecar container to your `docker-compose.production.yml`:

```yaml
services:
  web:
    # ... existing web service config ...
    depends_on:
      - litestream

  litestream:
    image: litestream/litestream:latest
    container_name: campfire-litestream
    restart: unless-stopped
    volumes:
      - /disk/campfire:/data  # Same volume as web service
      - ./config/litestream.yml:/etc/litestream.yml:ro
    environment:
      LITESTREAM_REPLICA_BUCKET: ${LITESTREAM_REPLICA_BUCKET}
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
      AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION:-auto}
      LITESTREAM_REPLICA_ENDPOINT: ${LITESTREAM_REPLICA_ENDPOINT:-}
    entrypoint: ["/usr/local/bin/litestream"]
    command: ["replicate"]

  # ... other services (caddy, etc.) ...
```

### Option 2: Procfile Process

Add Litestream as a process in your `Procfile`:

```
web: bin/start-app
redis: redis-server config/redis.conf
workers: FORK_PER_JOB=false INTERVAL=0.1 bundle exec resque-pool
scheduler: bundle exec resque-scheduler
litestream: litestream replicate
```

This requires installing Litestream in your Docker image.

### Option 3: Standalone Litestream Service

Run Litestream on the same host but as a separate systemd service or cron job.

## Configuration

### Step 1: Create Litestream Configuration

Create `config/litestream.yml`:

```yaml
dbs:
  - path: /data/db/production.sqlite3  # Adjust path based on your volume mount
    replicas:
      - type: s3
        bucket: $LITESTREAM_REPLICA_BUCKET
        path: campfire-db
        region: $AWS_DEFAULT_REGION
        endpoint: $LITESTREAM_REPLICA_ENDPOINT  # Optional, for R2
        sync-interval: 10s        # Replicate every 10 seconds
        retention: 168h           # Keep backups for 7 days
        snapshot-interval: 24h    # Daily snapshots
```

### Step 2: Configure Storage Backend

Choose either **Cloudflare R2** (recommended) or **AWS S3**.

#### Option A: Cloudflare R2 (Recommended)

**Why R2?**
- Zero egress fees (unlike S3)
- Cheaper: $0.015/GB/month vs S3's $0.023/GB/month
- S3-compatible API
- First 10GB free

**Setup:**

1. Create R2 bucket at https://dash.cloudflare.com/ (e.g., `campfire-backups`)
2. Generate API token with "Object Read & Write" permissions
3. Get your Cloudflare Account ID from the R2 dashboard
4. Add to your `.env` file:

```bash
# AWS/S3 credentials (used for file storage AND Litestream)
AWS_ACCESS_KEY_ID=your-r2-access-key-id
AWS_SECRET_ACCESS_KEY=your-r2-secret-access-key
AWS_DEFAULT_REGION=auto

# Litestream configuration
LITESTREAM_REPLICA_BUCKET=campfire-backups
LITESTREAM_REPLICA_ENDPOINT=https://YOUR-ACCOUNT-ID.r2.cloudflarestorage.com
```

#### Option B: AWS S3

1. Create S3 bucket (e.g., `campfire-backups`)
2. Add to your `.env` file:

```bash
LITESTREAM_REPLICA_BUCKET=campfire-backups
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key
AWS_DEFAULT_REGION=us-east-1
```

### Step 3: Verify SQLite WAL Mode

Litestream requires SQLite to use WAL (Write-Ahead Logging) mode. Check your `config/database.yml`:

```yaml
production:
  adapter: sqlite3
  database: storage/db/production.sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000
  # Ensure these are set:
  flags:
    - SQLITE_OPEN_READWRITE
    - SQLITE_OPEN_CREATE
  # WAL mode is typically set via initializer or pragma
```

You may need to enable WAL mode explicitly in an initializer or via SQL:

```ruby
# config/initializers/sqlite3.rb
ActiveSupport.on_load(:active_record_sqlite3adapter) do
  ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
end
```

## Monitoring

### Check Replication Status

If using docker-compose:

```bash
docker compose logs litestream -f
```

If using Kamal with Procfile:

```bash
kamal app logs -f | grep litestream
```

### Manual Commands

Access the Litestream container/process and run:

```bash
# List databases being replicated
litestream databases

# View snapshots
litestream snapshots <database-path>

# View WAL files
litestream wal <database-path>
```

## Restoration

### Full Database Restore

1. **Stop the application** to prevent database writes during restore
2. **Backup current database** (if it exists):
   ```bash
   cp storage/db/production.sqlite3 storage/db/production.sqlite3.backup
   ```
3. **Restore from Litestream**:
   ```bash
   litestream restore -o storage/db/production.sqlite3 <replica-url>
   ```

   Example with R2:
   ```bash
   litestream restore -o storage/db/production.sqlite3 \
     s3://campfire-backups/campfire-db
   ```

4. **Restart the application**

### Point-in-Time Restore

Restore to a specific timestamp:

```bash
litestream restore -o storage/db/production.sqlite3 \
  -timestamp 2024-01-15T12:00:00Z \
  s3://campfire-backups/campfire-db
```

### Restore to Specific Generation

List available generations:

```bash
litestream generations s3://campfire-backups/campfire-db
```

Restore specific generation:

```bash
litestream restore -o storage/db/production.sqlite3 \
  -generation <generation-id> \
  s3://campfire-backups/campfire-db
```

## Cost Optimization

### Storage Cost Comparison

**Cloudflare R2:**
- Storage: $0.015/GB/month
- Egress: FREE
- First 10 GB: FREE
- Example: 500MB database = **$0.00/month** (under free tier)
- Example: 20GB database = **$0.15/month**

**AWS S3:**
- Storage: $0.023/GB/month
- Egress: $0.09/GB (expensive for restores!)
- No free tier for storage
- Example: 500MB database = **$0.01/month + egress fees**
- Example: 20GB database = **$0.46/month + egress fees**

**Restoring from S3 can cost $1.80 in egress fees for a 20GB database!**

### Retention Policy

Adjust retention in `config/litestream.yml`:

```yaml
retention: 168h  # 7 days (balanced)
retention: 72h   # 3 days (lower cost)
retention: 720h  # 30 days (higher cost, more recovery options)
```

## Troubleshooting

### Verify Environment Variables

Ensure all required variables are set in your deployment environment.

### Check S3 Permissions

Your credentials need these permissions:
- `s3:GetObject`
- `s3:PutObject`
- `s3:DeleteObject`
- `s3:ListBucket`

### Database Lock Issues

If you see "database is locked" errors:
1. Verify only one Litestream process is running
2. Check SQLite timeout setting in `config/database.yml`
3. Ensure WAL mode is enabled

### Replication Lag

If replication falls behind:
1. Check disk I/O performance
2. Verify network connectivity to S3
3. Review `sync-interval` setting

## Advanced Usage

### Multiple Replicas

Configure redundant backups to multiple regions:

```yaml
dbs:
  - path: storage/db/production.sqlite3
    replicas:
      - type: s3
        bucket: primary-backup-bucket
        path: campfire-db
        region: us-east-1

      - type: s3
        bucket: secondary-backup-bucket
        path: campfire-db
        region: us-west-2
```

### Custom Backup Schedule

Modify snapshot frequency:

```yaml
snapshot-interval: 1h   # Hourly snapshots
snapshot-interval: 12h  # Twice daily
snapshot-interval: 168h # Weekly
```

## Alternative: Manual SQLite Backups

If you prefer not to use Litestream, consider these alternatives:

### 1. Periodic Tar Backups

```bash
# In crontab (daily at 2 AM)
0 2 * * * tar -czf /backups/campfire-$(date +\%Y\%m\%d).tar.gz /disk/campfire/db/production.sqlite3
```

### 2. SQLite `.backup` Command

```bash
sqlite3 storage/db/production.sqlite3 ".backup '/backups/backup.db'"
```

### 3. Volume Snapshots

If using cloud VMs, schedule regular volume snapshots through your provider (DigitalOcean, AWS, etc.).

## References

- [Litestream Documentation](https://litestream.io/)
- [Litestream Docker Setup](https://litestream.io/guides/docker/)
- [Litestream Configuration Reference](https://litestream.io/reference/config/)
- [Disaster Recovery Guide](https://litestream.io/guides/disaster-recovery/)
- [Cloudflare R2 Documentation](https://developers.cloudflare.com/r2/)
