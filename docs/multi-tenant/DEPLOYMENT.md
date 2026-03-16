# Deploying Multi-Tenant (SaaS Mode)

This guide covers deploying Sabha in multi-tenant SaaS mode, where multiple workspaces share a single application instance with isolated databases.

For single-tenant self-hosting, see [DEPLOYMENT.md](../DEPLOYMENT.md).

> **License note:** The multi-tenant SaaS engine (`saas/` directory) is licensed under the [Sabha SaaS License](../../saas/LICENSE), not MIT. The core application (everything outside `saas/`) remains MIT-licensed. You can freely read and reference this code for development and testing, but production use of the SaaS engine requires a Sabha subscription. See [LICENSE.md](../../LICENSE.md) for details.

---

## Overview

Multi-tenant mode enables:

- **Multiple workspaces** - Each workspace has its own isolated SQLite database
- **Shared authentication** - Users authenticate once, access multiple workspaces
- **Path-based routing** - URLs include workspace ID (e.g., `/1000001/rooms/general`)
- **Cross-workspace sessions** - Single sign-on across all workspaces

---

## Requirements

- A VPS with 4GB+ RAM (scales with number of workspaces)
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

After first deployment, set up the untenanted database and create your first workspace:

```bash
kamal console -d multitenant
```

```ruby
# In Rails console
Sabha::Saas::Setup.call

# Or create a workspace manually
workspace = Workspace.create!(name: "My Workspace")
puts "Workspace created with ID: #{workspace.id}"
# Access at: https://sabha.co/#{workspace.id}/
```

---

## Architecture

### Database Structure

Multi-tenant mode uses PostgreSQL for the shared layer and SQLite per workspace:

```
PostgreSQL (sabha_untenanted_production):
├── global_identities           # Cross-workspace user identity
├── global_sessions             # Cross-workspace sessions
├── workspaces                  # Workspace registry
├── workspace_memberships       # Identity-to-workspace links
├── auth_codes                  # OTP codes
└── workspace_external_id_sequences

/rails/storage/production/
└── workspaces/
    ├── 1000001/
    │   └── main.sqlite3        # Workspace 1 data (User, Room, Message, etc.)
    ├── 1000002/
    │   └── main.sqlite3        # Workspace 2 data
    └── ...
```

### Key Models

**Untenanted (shared across all workspaces):**
- `GlobalIdentity` - User identity (email, cross-workspace profile)
- `GlobalSession` - Authentication sessions
- `Workspace` - Workspace metadata
- `WorkspaceMembership` - Links identities to workspaces

**Tenanted (per-workspace):**
- `User` - Workspace-specific user record
- `Room`, `Message`, `Membership` - All chat data

### URL Structure

```
https://sabha.co/                     # Landing page
https://sabha.co/session/new          # Global sign-in
https://sabha.co/workspaces           # Workspace selector
https://sabha.co/1000001/             # Workspace 1 home
https://sabha.co/1000001/rooms/general # Room in workspace 1
```

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

### Create a Workspace

```bash
kamal console -d multitenant
```

```ruby
workspace = Workspace.create!(name: "Acme Corp")
puts "URL: https://sabha.co/#{workspace.id}/"
```

### List Workspaces

```ruby
Workspace.all.each { |w| puts "#{w.id}: #{w.name}" }
```

### Delete a Workspace

```ruby
workspace = Workspace.find(1000001)
workspace.destroy  # Deletes workspace and its database
```

### Workspace Info

```ruby
workspace = Workspace.find(1000001)
puts "Name: #{workspace.name}"
puts "Created: #{workspace.created_at}"
puts "Members: #{workspace.workspace_memberships.count}"
```

---

## Backups

The untenanted database (PostgreSQL) is managed externally — backups are handled by your provider (e.g., PlanetScale). Tenant SQLite databases need local backup.

### Tenant Database Backup

```bash
# SSH to server
ssh root@your-server

# Checkpoint all tenant databases
docker exec sabha-multitenant-web bin/rails runner "
  Workspace.find_each do |w|
    Tenant.switch(w.id) do
      ActiveRecord::Base.connection.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    end
  end
"

# Create backup archive of tenant data
cd /disk/sabha
tar -czf ~/backup-$(date +%Y%m%d).tar.gz .
```

### Restore Tenant Data

```bash
kamal app stop -d multitenant
ssh root@your-server "cd /disk/sabha && rm -rf * && tar -xzf /tmp/backup.tar.gz"
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
  Tenant.switch(w.id) do
    size = ActiveRecord::Base.connection.execute(
      "SELECT page_count * page_size / 1024 / 1024.0 as mb FROM pragma_page_count(), pragma_page_size();"
    ).first["mb"]
    puts "Workspace #{w.id} (#{w.name}): #{size.round(2)} MB"
  end
end
```

### Active Users

```ruby
# Users active in last 24 hours across all workspaces
count = 0
Workspace.find_each do |w|
  Tenant.switch(w.id) do
    count += User.where("last_seen_at > ?", 24.hours.ago).count
  end
end
puts "Active users (24h): #{count}"
```

---

## Scaling Considerations

### When to Scale

- **CPU**: Sustained >70% usage
- **Memory**: Sustained >80% usage
- **Disk**: >80% full
- **Workspaces**: >100 active workspaces on a single server

### Scaling Options

1. **Vertical scaling** - Upgrade to larger VPS (easiest)
2. **Read replicas** - Use Litestream for SQLite replication
3. **Multiple servers** - Route workspaces to different servers by ID range

### Performance Tips

- Enable AnyCable for WebSocket scaling (`ANYCABLE_ENABLED=true`)
- Use S3/R2 for file storage instead of local disk
- Set up CDN for static assets
- Monitor SQLite WAL file sizes

---

## Troubleshooting

### "Workspace not found"

```ruby
# Check workspace exists
Workspace.find_by(id: 1000001)

# List all workspaces
Workspace.pluck(:id, :name)
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
# Recreate workspace database
workspace = Workspace.find(1000001)
Tenant.switch(workspace.id) do
  ActiveRecord::Tasks::DatabaseTasks.create_current
  ActiveRecord::Tasks::DatabaseTasks.migrate
end
```

---

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `SAAS` | Yes | Set to `true` for multi-tenant mode |
| `SERVER_IP` | Yes | Server IP address |
| `PROXY_HOST` | Yes | Domain name |
| `COOKIE_DOMAIN` | Yes | Domain for session cookies (cross-workspace) |
| `SECRET_KEY_BASE` | Yes | Rails encryption key |
| `UNTENANTED_DATABASE_URL` | Yes | Managed PostgreSQL connection URL |
| `EMAIL_PROVIDER` | No | `resend` (default) or `ses` |
| `RESEND_API_KEY` | If Resend | Resend API key |
| `AWS_SES_REGION` | If SES | AWS SES region |
| `AWS_SES_ACCESS_KEY_ID` | If SES | AWS SES access key |
| `AWS_SES_SECRET_ACCESS_KEY` | If SES | AWS SES secret key |
| `VAPID_PUBLIC_KEY` | Yes | Web push public key |
| `VAPID_PRIVATE_KEY` | Yes | Web push private key |
| `ANYCABLE_ENABLED` | No | Enable AnyCable (default: true) |
| `ANYCABLE_SECRET` | If AnyCable | AnyCable authentication secret |
| `KAMAL_REGISTRY_PASSWORD` | Yes | GitHub Container Registry token |

---

## See Also

- [activerecord-tenanted Guide](activerecord-tenanted-guide.md)
- [GlobalIdentity Sync](global-identity-user-sync.md)
- [PostgreSQL Decision](postgres-untenanted.md)
- [Self-Hosted Deployment](../DEPLOYMENT.md)
