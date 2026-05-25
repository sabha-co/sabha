# Deploying Multi-Tenant (SaaS Mode)

This guide covers deploying Sabha in multi-tenant SaaS mode, where multiple workspaces share a single application instance with isolated databases.

For single-tenant self-hosting, see [DEPLOYMENT.md](../DEPLOYMENT.md).

> **License note:** Sabha is based on Campfire, which is single-tenant by design and MIT-licensed. We added multi-tenancy on top to power the free communities at [sabha.co](https://sabha.co), and that engine lives in `saas/` under the separately-licensed [Sabha SaaS License](../../saas/LICENSE) rather than MIT. The core application (everything outside `saas/`) remains MIT-licensed. You can freely read and reference the SaaS code for development and testing, but production use of the SaaS engine requires a Sabha subscription. See [LICENSE.md](../../LICENSE.md) for details.

---

## Overview

Multi-tenant mode enables:

- **Multiple workspaces** - Each workspace has its own isolated SQLite database
- **Shared authentication** - Users authenticate once, access multiple workspaces
- **Path-based routing** - URLs include workspace ID (e.g., `/1000001/rooms/general`)
- **Cross-workspace sessions** - Single sign-on across all workspaces

---

## Requirements

- A VPS with 8GB+ RAM (scales with number of workspaces)
- A domain name pointing to your server
- A managed PostgreSQL instance (e.g., PlanetScale Postgres) for the untenanted database
- Docker and Kamal installed locally
- GitHub Container Registry access (or your own registry)

---

## Deploying with Kamal

### 1. Configure Environment

```bash
cp .env.multitenant.sample .env.multitenant
```

Edit `.env.multitenant`:

See `.env.multitenant.sample` for a complete reference. Key variables:

```bash
# Server
SERVER_IP=your.server.ip
PROXY_HOST=yourdomain.com

# Branding
APP_NAME="Your Platform"
APP_SHORT_NAME="Platform"
APP_DESCRIPTION="Community workspaces powered by Sabha"
APP_HOST="yourdomain.com"

# Email
SUPPORT_EMAIL="support@yourdomain.com"
MAILER_FROM_NAME="Your Platform"
MAILER_FROM_EMAIL="noreply@yourdomain.com"

# IMPORTANT: Cookie domain enables cross-workspace sessions
COOKIE_DOMAIN=yourdomain.com

# Managed PostgreSQL for the untenanted database
UNTENANTED_DATABASE_URL=postgres://user:password@host:port/database?sslmode=require

# Rails
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Email provider: "resend" (default) or "ses"
EMAIL_PROVIDER=resend
RESEND_API_KEY=your_resend_api_key
# Or for AWS SES:
# EMAIL_PROVIDER=ses
# AWS_SES_REGION=us-east-1
# AWS_SES_ACCESS_KEY_ID=
# AWS_SES_SECRET_ACCESS_KEY=

# Platform-wide kill switch for outbound notification mail. Setting this to the
# literal string "true" makes Sabha.email_configured? return false everywhere:
# the Email admin section disappears from every workspace, missed-notification
# bundles stop being created, and the weekly digest job short-circuits before
# any per-user iteration. Per-workspace toggles in the DB stay untouched, so
# flipping it back off restores each workspace's prior preference. Requires a
# restart to take effect.
# EMAIL_GLOBALLY_DISABLED=true

# Web Push (generate with: npx web-push generate-vapid-keys)
VAPID_PUBLIC_KEY=your_public_key
VAPID_PRIVATE_KEY=your_private_key

# AnyCable (high-performance WebSockets)
ANYCABLE_ENABLED=true
ANYCABLE_SECRET=$(openssl rand -hex 32)

# Cloudflare Turnstile CAPTCHA (optional)
# CLOUDFLARE_TURNSTILE_SITE_KEY=
# CLOUDFLARE_TURNSTILE_SECRET_KEY=

# Docker registry
KAMAL_REGISTRY_PASSWORD=your_github_token
```

### 2. Deploy

```bash
# First-time setup (provisions server, starts services)
kamal setup -d multitenant

# Subsequent deployments
kamal deploy -d multitenant
```

### 3. Initialize SaaS Database

After first deployment, run the SaaS setup task to migrate the untenanted database and create the default workspace:

```bash
kamal app exec -d multitenant "bin/rails saas:setup"
```

The task reads `ADMIN_EMAIL` and `WORKSPACE_NAME` (both optional) to seed the first `GlobalIdentity` and `Workspace`. See `lib/tasks/saas.rake` for the exact behavior.

To create additional workspaces manually:

```bash
kamal console -d multitenant
```

```ruby
creator = GlobalIdentity.find_or_create_by!(email_address: "you@example.com")
creator.verify! unless creator.verified?

workspace = Workspace.create_with_database!(name: "My Workspace", creator: creator)
puts "Workspace external ID: #{workspace.external_id}"
# Access at: https://sabha.co/#{workspace.external_id}/
```

`create_with_database!` provisions the per-workspace SQLite database, the membership for the creator, and the default rooms — plain `Workspace.create!` would leave the tenant DB uninitialized.

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full architecture overview (database structure, key models, URL routing, request flow).

---

## Configuration Differences

| Setting | Self-Hosted | Multi-Tenant |
|---------|-------------|--------------|
| `SAAS` | Not set | `true` |
| `COOKIE_DOMAIN` | Optional | Required (e.g., `yourdomain.com`) |
| `UNTENANTED_DATABASE_URL` | Not needed | Required (managed Postgres URL) |
| `EMAIL_PROVIDER` | `resend` only | `resend` or `ses` |
| Database | Single SQLite | Managed Postgres (shared) + SQLite per workspace |
| Auth | Password or OTP | OTP via GlobalIdentity |

---

## Kamal Commands

```bash
# Deploy
kamal deploy -d multitenant

# View logs
kamal logs -d multitenant

# Rails console
kamal console -d multitenant

# Shell access
kamal shell -d multitenant

# Database console
kamal dbc -d multitenant

# Stop/start
kamal app stop -d multitenant
kamal app boot -d multitenant
```

---

## Workspace Management

Workspaces are addressed by `external_id` (the visible URL ID, e.g. `1000001`), not the PK `id`. All tenant-scoped APIs take the external ID as a string.

### Create a Workspace

```bash
kamal console -d multitenant
```

```ruby
creator = GlobalIdentity.find_or_create_by!(email_address: "owner@example.com")
creator.verify! unless creator.verified?

workspace = Workspace.create_with_database!(name: "Acme Corp", creator: creator)
puts "URL: https://sabha.co/#{workspace.external_id}/"
```

### List Workspaces

```ruby
Workspace.all.each { |w| puts "#{w.external_id}: #{w.name}" }
```

### Delete a Workspace

```ruby
workspace = Workspace.find_by!(external_id: 1000001)
workspace.destroy_with_database!
```

`destroy_with_database!` captures admin emails, creates a final R2 backup (if R2 is configured), purges old backups, destroys the workspace row and its memberships, emails the admins, and asynchronously purges ActiveStorage blobs and the tenant SQLite file via `Workspace::PurgeStorageJob`. Plain `destroy` would leave the SQLite database orphaned on disk.

### Workspace Info

```ruby
workspace = Workspace.find_by!(external_id: 1000001)
puts "Name: #{workspace.name}"
puts "Created: #{workspace.created_at}"
puts "Members: #{workspace.workspace_memberships.count}"
```

---

## Backups

The untenanted database (PostgreSQL) is managed externally — backups are handled by your provider. Tenant SQLite databases are backed up via the `Workspace::Backup` system, which uploads consistent SQLite snapshots to Cloudflare R2.

### R2-backed tenant backups (default)

Configure R2 in `.env.multitenant`:

```bash
R2_ACCESS_KEY_ID=...
R2_SECRET_ACCESS_KEY=...
R2_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
R2_BUCKET=sabha-backups
```

When R2 is configured, `Workspace::Backup.create_from_database!(workspace)` writes a snapshot to `backups/<external_id>/<timestamp>-<rand>.sqlite3` in R2 and records a `workspace_backups` row. Default retention is 7 days (`Workspace::Backup::RETENTION_PERIOD`); `Workspace::Backup.purge_expired!` deletes expired snapshots.

A final `final-*.sqlite3` backup is created automatically when a workspace is destroyed (see [Delete a Workspace](#delete-a-workspace)).

Trigger a manual backup of every workspace:

```ruby
Workspace.find_each do |workspace|
  Workspace::Backup.create_from_database!(workspace)
end
```

### Filesystem fallback (no R2)

If R2 is not configured, snapshot the on-disk SQLite files directly. The `/disk/sabha` host volume is mounted at `/rails/storage` inside the container.

```bash
ssh sabha@your-server

# Checkpoint WAL across all tenant databases before snapshotting
docker exec sabha-web bin/rails runner '
  Workspace.find_each do |w|
    ApplicationRecord.with_tenant(w.external_id.to_s) do
      ActiveRecord::Base.connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    end
  end
'

sudo tar -czf ~/backup-$(date +%Y%m%d).tar.gz -C /disk/sabha workspaces
```

### Restore Tenant Data

```bash
kamal app stop -d multitenant
ssh sabha@your-server "sudo rm -rf /disk/sabha/workspaces && sudo tar -xzf /tmp/backup.tar.gz -C /disk/sabha"
kamal app boot -d multitenant
```

---

## Monitoring

### Health Check

```bash
curl -f https://sabha.co/up && echo "OK" || echo "FAIL"
```

### Database Sizes

```bash
kamal console -d multitenant
```

```ruby
# Untenanted database size (managed Postgres)
size = UntenantedRecord.connection.execute("SELECT pg_database_size(current_database()) / 1024 / 1024.0 AS mb").first["mb"]
puts "Untenanted (Postgres): #{size.round(2)} MB"

# Per-workspace sizes (SQLite)
Workspace.find_each do |w|
  ApplicationRecord.with_tenant(w.external_id.to_s) do
    size = ActiveRecord::Base.connection.execute(
      "SELECT page_count * page_size / 1024 / 1024.0 as mb FROM pragma_page_count(), pragma_page_size();"
    ).first["mb"]
    puts "Workspace #{w.external_id} (#{w.name}): #{size.round(2)} MB"
  end
end
```

### Active Users

```ruby
# Users active in last 24 hours across all workspaces
count = 0
Workspace.find_each do |w|
  ApplicationRecord.with_tenant(w.external_id.to_s) do
    count += User.where("last_seen_at > ?", 24.hours.ago).count
  end
end
puts "Active users (24h): #{count}"
```

---
## Troubleshooting

### "Workspace not found"

```ruby
# Check workspace exists (external_id is the URL-visible ID)
Workspace.find_by(external_id: 1000001)

# List all workspaces
Workspace.pluck(:external_id, :name)
```

### Cross-workspace session issues

Verify `COOKIE_DOMAIN` is set correctly:

```bash
kamal app exec -d multitenant 'echo $COOKIE_DOMAIN'
```

Must match your domain (e.g., `sabha.co`, not `www.sabha.co`).

### Database locked errors

```bash
# Stop app, wait, restart
kamal app stop -d multitenant
sleep 10
kamal app boot -d multitenant
```

### Missing workspace database

```ruby
# Recreate workspace database (idempotent — skips if already present)
workspace = Workspace.find_by!(external_id: 1000001)
tenant_id = workspace.external_id.to_s
ApplicationRecord.create_tenant(tenant_id) unless ApplicationRecord.tenant_exist?(tenant_id)
```

To restore the contents from R2, see [Backups](#backups) above.

---

## Environment Variables Reference

See `.env.multitenant.sample` for the authoritative list. The variables actually wired into the deploy are declared in `config/deploy.multitenant.yml`.

### Required

| Variable | Description |
|----------|-------------|
| `SAAS` | Set to `true` for multi-tenant mode (set by `deploy.multitenant.yml`) |
| `SERVER_IP` | Server IP address |
| `PROXY_HOST` | Domain name handled by kamal-proxy |
| `COOKIE_DOMAIN` | Cookie scope for cross-workspace sessions (e.g. `sabha.co`) |
| `SECRET_KEY_BASE` | Rails encryption key (generate with `rails secret`) |
| `UNTENANTED_DATABASE_URL` | Managed PostgreSQL connection URL |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` | Web push keys (`npx web-push generate-vapid-keys`) |
| `KAMAL_REGISTRY_PASSWORD` | GitHub Container Registry token |

### Branding

| Variable | Description |
|----------|-------------|
| `APP_NAME`, `APP_SHORT_NAME`, `APP_DESCRIPTION`, `APP_HOST` | App identity strings |
| `SUPPORT_EMAIL`, `MAILER_FROM_NAME`, `MAILER_FROM_EMAIL` | Outbound mail headers |
| `THEME_COLOR`, `BACKGROUND_COLOR` | PWA chrome colors |

### Email

| Variable | Required | Description |
|----------|----------|-------------|
| `EMAIL_PROVIDER` | No | `resend` (default) or `ses` |
| `RESEND_API_KEY` | If Resend | Resend API key |
| `AWS_SES_REGION`, `AWS_SES_ACCESS_KEY_ID`, `AWS_SES_SECRET_ACCESS_KEY`, `SES_CONFIGURATION_SET` | If SES | AWS SES credentials |
| `EMAIL_GLOBALLY_DISABLED` | No | Platform-wide kill switch for notification mail (transactional auth mail still sends) |

### WebSockets (AnyCable)

| Variable | Description |
|----------|-------------|
| `ANYCABLE_ENABLED` | `true` to route `/cable` to the AnyCable-Go accessory |
| `ANYCABLE_SECRET` | Shared secret between Puma and AnyCable-Go (required when enabled) |

### Tenant backups (R2)

| Variable | Description |
|----------|-------------|
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | Cloudflare R2 credentials |
| `R2_ENDPOINT` | `https://<account-id>.r2.cloudflarestorage.com` |
| `R2_BUCKET` | Bucket name (e.g. `sabha-backups`) |

When all R2 vars are set, `Workspace::Backup` is active and final backups run on workspace deletion.

### Optional

| Variable | Description |
|----------|-------------|
| `ADMIN_EMAIL` | Default `GlobalIdentity` email used by `bin/rails saas:setup` |
| `WORKSPACE_NAME` | Default workspace name used by `bin/rails saas:setup` |
| `CLOUDFLARE_TURNSTILE_SITE_KEY`, `CLOUDFLARE_TURNSTILE_SECRET_KEY` | Turnstile CAPTCHA on sign-up |
| `CSP_FRAME_ANCESTORS` | Override default `frame-ancestors` CSP directive |
| `UMAMI_WEBSITE_ID`, `UMAMI_HOST` | Umami analytics |
| `SENTRY_DSN` | Sentry error tracking |

---

## See Also

- [activerecord-tenanted Guide](activerecord-tenanted-guide.md)
- [PostgreSQL Decision](postgres-untenanted.md)
- [Self-Hosted Deployment](../DEPLOYMENT.md)
