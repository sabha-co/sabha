# Litestream Database Backup Guide

This guide covers Litestream integration for Campfire-CE when deployed via **docker-compose** (e.g., through [campfire_cloud](https://github.com/yourusername/campfire_cloud)).

## Overview

When deploying Campfire-CE via docker-compose, Litestream runs as a **sidecar container** that continuously replicates your SQLite database to S3-compatible storage:

- **Automatic setup** - Works out-of-the-box with docker-compose deployments
- **Continuous replication** - Changes replicated every 10 seconds
- **Point-in-time recovery** - Restore to any point within the retention window
- **Minimal overhead** - Runs in a separate container with low resource usage
- **Automatic snapshots** - Daily snapshots for faster restoration
- **30-day retention** - Keeps backups for 30 days by default

## Deployment Methods

Campfire-CE supports two deployment methods:

| Method | Backup Solution | Status |
|--------|----------------|---------|
| **Docker Compose** | ✅ Litestream sidecar (automatic) | Recommended |
| **Kamal** (standalone) | ⚠️ Manual backup setup required | Self-managed |

**This guide covers the docker-compose approach only.**

## Setup

You can use either **AWS S3** or **Cloudflare R2** for backups. R2 is recommended for its zero egress fees and lower costs.

### Option A: Cloudflare R2 (Recommended)

**Why R2?**
- Zero egress fees (unlike S3)
- Cheaper: $0.015/GB/month vs S3's $0.023/GB/month
- S3-compatible API
- First 10GB free

#### 1. Create R2 Bucket

1. Go to https://dash.cloudflare.com/
2. Click "R2" in the left sidebar
3. Click "Create bucket"
4. Bucket name: `campfire-backups` (or your preferred name)
5. Location: Automatic
6. Click "Create bucket"

#### 2. Generate R2 API Token

1. In R2 dashboard, click "Manage R2 API Tokens"
2. Click "Create API token"
3. Token name: `Campfire Backups`
4. Permissions: **Object Read & Write**
5. Bucket scope: Apply to `campfire-backups` only
6. Click "Create API Token"
7. **Copy these values** (shown only once):
   - Access Key ID
   - Secret Access Key

#### 3. Get Your Cloudflare Account ID

Your Account ID is visible in the R2 dashboard URL or sidebar (format: `abc123...`)

#### 4. Configure Environment Variables

Add to your `.env` file or `.kamal/secrets`:

```bash
# Use your R2 credentials (same can be used for file storage)
AWS_ACCESS_KEY_ID=your-r2-access-key-id
AWS_SECRET_ACCESS_KEY=your-r2-secret-access-key
AWS_DEFAULT_REGION=auto

# Litestream backup configuration
LITESTREAM_REPLICA_BUCKET=campfire-backups
LITESTREAM_REPLICA_ENDPOINT=https://YOUR-ACCOUNT-ID.r2.cloudflarestorage.com
```

**Important:** Replace `YOUR-ACCOUNT-ID` with your actual Cloudflare Account ID.

### Option B: AWS S3

#### 1. Create S3 Bucket

Create an S3 bucket for your database backups:
- Use a dedicated bucket: `campfire-backups`
- Or use your existing bucket with a dedicated path

#### 2. Set Environment Variables

Add to your `.env` file or `.kamal/secrets`:

```bash
# S3 configuration
LITESTREAM_REPLICA_BUCKET=your-backup-bucket-name
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key
AWS_DEFAULT_REGION=us-east-1
```

No additional configuration needed - the default `config/litestream.yml` works with S3.

### 3. Deploy

Litestream runs automatically as part of the Procfile when you deploy:

```bash
kamal deploy
```

## Configuration

### Main Configuration

The Litestream configuration is in `config/litestream.yml`:

```yaml
dbs:
  - path: storage/db/production.sqlite3
    replicas:
      - type: s3
        bucket: $LITESTREAM_REPLICA_BUCKET
        path: campfire-db
        region: $LITESTREAM_REPLICA_REGION
        sync-interval: 10s        # Replicate every 10 seconds
        retention: 168h           # Keep backups for 7 days
        snapshot-interval: 24h    # Daily snapshots
```

### Rails Integration

The Rails initializer (`config/initializers/litestream.rb`) maps your existing AWS credentials to Litestream ENV variables.

## Monitoring

### Check Replication Status

View the Litestream process logs:

```bash
kamal app logs -f | grep litestream
```

### List Databases

```bash
kamal app exec 'bin/rails litestream:databases'
```

### View Snapshots

```bash
kamal app exec 'bin/rails litestream:snapshots'
```

### View WAL Files

```bash
kamal app exec 'bin/rails litestream:wal'
```

## Restoration

### Full Database Restore

If you need to restore your database from a backup:

1. **Stop the application**:
   ```bash
   kamal app stop
   ```

2. **Backup current database** (if it exists):
   ```bash
   kamal app exec 'cp storage/db/production.sqlite3 storage/db/production.sqlite3.backup'
   ```

3. **Restore from Litestream**:
   ```bash
   kamal app exec 'bin/rails litestream:restore -- -database=storage/db/production.sqlite3'
   ```

4. **Restart the application**:
   ```bash
   kamal app start
   ```

### Point-in-Time Restore

To restore to a specific point in time:

```bash
kamal app exec 'bin/rails litestream:restore -- -database=storage/db/production.sqlite3 -timestamp=2024-01-15T12:00:00Z'
```

### Restore to Specific Generation

List available generations:

```bash
kamal app exec 'bin/rails litestream:generations -- -database=storage/db/production.sqlite3'
```

Restore specific generation:

```bash
kamal app exec 'bin/rails litestream:restore -- -database=storage/db/production.sqlite3 -generation=<generation-id>'
```

## Local Development

For local testing with Litestream:

1. **Set environment variables** in `.env`:
   ```bash
   LITESTREAM_REPLICA_BUCKET=your-test-bucket
   ```

2. **Run Litestream manually**:
   ```bash
   bin/rails litestream:replicate
   ```

3. **Or run with Procfile**:
   ```bash
   bin/boot
   ```

## Troubleshooting

### Verify Configuration

Check that environment variables are properly set:

```bash
bin/rails litestream:env
```

### Check S3 Permissions

Ensure your AWS credentials have these permissions for the bucket:

- `s3:GetObject`
- `s3:PutObject`
- `s3:DeleteObject`
- `s3:ListBucket`

### Database Lock Issues

If you see "database is locked" errors:

1. Check that only one Litestream process is running
2. Verify SQLite is configured with proper timeout (set in `config/database.yml`)
3. Ensure WAL mode is enabled (Litestream requires WAL mode)

### Replication Lag

If replication is falling behind:

1. Check disk I/O performance
2. Verify network connectivity to S3
3. Review `sync-interval` setting in `config/litestream.yml`

## Cost Optimization

### Storage Cost Comparison

**Cloudflare R2 (Recommended):**
- Storage: $0.015/GB/month
- Egress: FREE
- First 10 GB: FREE
- Example: 500MB database = **$0.00/month** (under free tier)
- Example: 20GB database = **$0.15/month**

**AWS S3:**
- Storage: $0.023/GB/month
- Egress: $0.09/GB (expensive!)
- No free tier for storage
- Example: 500MB database = **$0.01/month storage + egress fees**
- Example: 20GB database = **$0.46/month + egress fees**

**Typical storage usage for a Campfire database:**
- Base snapshot: ~10-100 MB (depends on your data)
- Daily growth: ~1-10 MB/day in WAL files
- Total monthly: ~100-500 MB

**Why R2 wins:**
- Zero egress fees (S3 charges every time you download/restore)
- Lower storage costs
- First 10GB free
- Restoring a backup from S3 can cost $1.80 for a 20GB database!

### Retention Policy

Adjust retention in `config/litestream.yml` to balance cost and recovery needs:

```yaml
retention: 168h  # 7 days (default)
retention: 72h   # 3 days (lower cost)
retention: 720h  # 30 days (higher cost, more recovery options)
```

### Storage Class

For long-term archival, consider using S3 Glacier or Intelligent-Tiering. Update `config/litestream.yml`:

```yaml
replicas:
  - type: s3
    # ... other config ...
    # Add storage class
    force-path-style: true
    # Note: Storage class must be set at bucket level or via S3 lifecycle policies
```

## Advanced Usage

### Multiple Replicas

You can configure multiple replicas for redundancy:

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

Modify snapshot frequency in `config/litestream.yml`:

```yaml
snapshot-interval: 1h   # Hourly snapshots
snapshot-interval: 12h  # Twice daily
snapshot-interval: 168h # Weekly
```

## References

- [Litestream Documentation](https://litestream.io/)
- [litestream-ruby GitHub](https://github.com/fractaledmind/litestream-ruby)
- [Litestream Configuration Reference](https://litestream.io/reference/config/)
- [Disaster Recovery Guide](https://litestream.io/guides/disaster-recovery/)
