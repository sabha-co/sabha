# Tenant Database Backup Plan

## Problem

Workspace SQLite databases live on a mounted volume (`/disk/sabha/`). If the volume fails or a container writes to ephemeral storage (as happened with workspace 1000002), tenant data is lost. PostgreSQL (untenanted) records survive but the actual workspace data does not.

## Solution

Two-layer backup: local snapshots via cron + remote sync via rclone to S3/R2.

## Why `.backup` API

Evaluated against other SQLite backup strategies ([reference](https://oldmoe.blog/2024/04/30/backup-strategies-for-sqlite-in-production/)):

| Method | Safe while live | Speed | Restore speed | Notes |
|--------|----------------|-------|---------------|-------|
| **`.backup` API** | Yes | Fast | Fast | Page-by-page replica, ignores concurrent writes. Our choice. |
| `VACUUM INTO` | Yes | Slower (CPU) | Fast | Produces optimized copy, but higher cost and less dedup-friendly |
| `.dump` | Yes | Slow | Slowest | SQL text output, good compression but slow restore |
| `cp --reflink` (CoW) | Needs txn wrapper | ~2ms | Fast | Requires Btrfs/XFS/ZFS, must copy WAL too |
| Litestream | Yes | Continuous | Slow (reassemble) | Overkill for daily backups, better for point-in-time recovery |

`.backup` is the right fit: safe with WAL mode (Rails default), no filesystem requirements, simple, fast enough for daily use.

## Architecture

```
Cron (daily, 3am UTC, sabha user)
  │
  ├─ Step 1: /disk/sabha/backup-databases
  │   SQLite .backup API (safe while app is running)
  │   /disk/sabha/workspaces/production/*/db/main.sqlite3
  │     → /disk/sabha/backups/{tenant_id}/{timestamp}.sqlite3
  │   Prune local backups older than 7 days
  │
  └─ Step 2 (TODO): rclone sync
      /disk/sabha/backups/ → remote:sabha-backups/
      Uses pre-configured rclone remote (S3 or R2)
```

## Current Setup

**Server:** `sabha-prod` (5.78.83.76), Ubuntu 24.04, Hetzner
**Volume:** `/disk/sabha/` (75GB, ext4, mounted at `/dev/sda1`)
**Container mount:** `/disk/sabha/` → `/rails/storage/` (via Kamal)
**User:** `sabha` (non-root)

### What's deployed

- Script: `/disk/sabha/backup-databases` (copied from repo `bin/backup-databases`)
- Cron: `sabha` user, daily at 3am UTC
- Logs: `/disk/sabha/logs/backup.log` (timestamped, written by script)
- Cron output: `/disk/sabha/logs/cron.log`

### Cron entry (sabha user)

```
0 3 * * * STORAGE=/disk/sabha /disk/sabha/backup-databases >> /disk/sabha/logs/cron.log 2>&1
```

### Manual run

```bash
ssh sabha-prod 'STORAGE=/disk/sabha /disk/sabha/backup-databases'
```

### Updating the script after code changes

```bash
ssh sabha-prod 'cat > /tmp/backup-databases && sudo mv /tmp/backup-databases /disk/sabha/backup-databases && sudo chmod +x /disk/sabha/backup-databases' < bin/backup-databases
```

## File Locations

| What | Path |
|------|------|
| Backup script (server) | `/disk/sabha/backup-databases` |
| Backup script (repo) | `bin/backup-databases` |
| Local backups | `/disk/sabha/backups/{tenant_id}/{timestamp}.sqlite3` |
| Script log | `/disk/sabha/logs/backup.log` |
| Cron log | `/disk/sabha/logs/cron.log` |
| Source databases | `/disk/sabha/workspaces/production/{tenant_id}/db/main.sqlite3` |

## Retention

- **Local**: 7 days (configurable via `RETENTION_DAYS`)

## Recovery

### From local backup

```bash
# 1. List available backups
ssh sabha-prod 'ls -lh /disk/sabha/backups/{tenant_id}/'

# 2. Stop the app to prevent writes during restore
set -a && source .env.multitenant && set +a
kamal app stop -d multitenant

# 3. Restore the backup
ssh sabha-prod 'cp /disk/sabha/backups/{tenant_id}/{timestamp}.sqlite3 \
   /disk/sabha/workspaces/production/{tenant_id}/db/main.sqlite3'

# 4. Fix ownership (container runs as UID 999)
ssh sabha-prod 'sudo chown 999:systemd-journal \
   /disk/sabha/workspaces/production/{tenant_id}/db/main.sqlite3'

# 5. Remove WAL/SHM files (stale after restore)
ssh sabha-prod 'rm -f /disk/sabha/workspaces/production/{tenant_id}/db/main.sqlite3-wal \
   /disk/sabha/workspaces/production/{tenant_id}/db/main.sqlite3-shm'

# 6. Restart the app
kamal app start -d multitenant
```

### From remote backup (once rclone is configured)

```bash
# Download from remote, then follow steps 2-6 above
ssh sabha-prod 'rclone copy sabha:sabha-backups/{tenant_id}/{timestamp}.sqlite3 /tmp/'
ssh sabha-prod 'cp /tmp/{timestamp}.sqlite3 \
   /disk/sabha/workspaces/production/{tenant_id}/db/main.sqlite3'
```

### Verify restore

```bash
# Quick check from the server
ssh sabha-prod 'sqlite3 /disk/sabha/workspaces/production/{tenant_id}/db/main.sqlite3 \
   "SELECT count(*) FROM users;"'

# Or via the app
set -a && source .env.multitenant && set +a
kamal app exec -d multitenant 'bin/rails runner "ApplicationRecord.with_tenant(\"{tenant_id}\") { puts User.count }"'
```

## Boot Safety

`bin/boot` aborts if `storage/` is not a mounted volume in SaaS production mode. This prevents tenant databases from being written to ephemeral container storage. See commit `f0383c6`.

## Open Decisions

- [ ] Which provider for remote backups: Cloudflare R2 or AWS S3?
- [ ] Failure alerting: email, Slack webhook, or other?
- [ ] Remote retention policy (longer than local 7 days?)
