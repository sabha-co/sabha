# Technical PRD: Multi-Tenancy for Campfire-CE

**Related Documents:**
- [Product PRD](./multi-tenancy-product-prd.md) - Business goals, user stories, requirements
- [Implementation Tasks](./multi-tenancy-plans-and-tasks.md) - Task breakdown
- [Architecture Notes](./multitenant-saas-notes.md) - Fizzy comparison and patterns
- [User Flows](./multi-tenant-user-flows.md) - Detailed user journeys

## Overview

Add multi-tenancy capability to Campfire-CE as an **opt-in SaaS layer**. The core application remains single-tenant and works out of the box for self-hosters. Multi-tenancy is enabled via the `saas/` folder (Rails engine) for those who want to run a multi-workspace deployment.

## Design Philosophy

**Core repo = Single-tenant by default**
- Fork, deploy, and run a single chat instance immediately
- Existing `Account` model handles settings (auth method, permissions, etc.)
- No shared database complexity required
- Perfect for open-source self-hosters

**SaaS layer = Multi-tenancy opt-in**
- `saas/` folder adds Workspace, GlobalIdentity, untenanted DB infrastructure
- Each workspace gets its own database with its own `Account` for settings
- GlobalIdentity allows users to switch workspaces without re-authenticating
- For those running multi-tenant SaaS deployments

## Goals

1. **Preserve single-tenant simplicity** - Core repo works without multi-tenancy overhead (true self-hosting)
2. **Enable multi-workspace deployment** - One Campfire instance serves many independent communities (via SaaS layer)
3. **Complete data isolation** - Each workspace's data in separate SQLite database files
4. **GlobalIdentity** - Users can switch between workspaces without re-authenticating
5. **Self-service workspace creation** - Users can create new workspaces themselves
6. **Simple operations** - Workspace backup/restore/deletion is file-system level
7. **Simple multi-tenant deployment** - Path-based routing, no wildcard DNS or SSL required

## Non-Goals (v1)

- Admin dashboard
- Billing/payment integration
- Cross-workspace search or analytics
- PostgreSQL/MySQL support (SQLite only)
- Subdomain-based routing (too complex for self-hosters)
- Removing or replacing the Account model (it stays for workspace-local settings)
- Data portability / workspace migration (v2 - architecture supports it, tooling deferred)

---

## Architecture

### Single-Tenant Mode (Core App - Default)

```
storage/
└── production.sqlite3         # Single database with all data
    ├── Account               # Settings (auth method, permissions)
    ├── User, Room, Message   # All application data
    └── ...
```

This is how the core open-source app works. No shared database, no workspace complexity.

### Multi-Tenant Mode (SaaS Layer - Opt-in)

When the `saas/` engine is enabled:

```
storage/
├── untenanted/
│   └── {env}.sqlite3                 # GlobalIdentity + workspace registry
└── workspaces/
    └── {env}/
        ├── 1000001/
        │   └── db/main.sqlite3       # Workspace 1000001's dataset
        ├── 1000002/
        │   └── db/main.sqlite3       # Workspace 1000002's dataset
        └── 1000003/
            └── db/main.sqlite3       # Workspace 1000003's dataset
```

### User Model: GlobalIdentity (Slack Like)

In multi-tenant mode, users have a single GlobalIdentity that spans all workspaces. When visiting a workspace, a workspace-specific User record is created from the GlobalIdentity.

```
┌─────────────────────────────────────────────────────────────┐
│                   Untenanted Database                       │
│                    (saas/ layer only)                       │
│                                                             │
│  ┌──────────┐  ┌───────────────┐  ┌─────────────────────┐  │
│  │GlobalIden│  │ GlobalSession │  │ WorkspaceMembership │  │
│  │ ───────  │  │ ───────────── │  │ ─────────────────── │  │
│  │ email    │←─│ identity_id   │  │ identity_id         │  │
│  │          │  │ token         │  │ tenant (ext_id)     │  │
│  │          │  │ expires_at    │  │                     │  │
│  └──────────┘  └───────────────┘  └─────────────────────┘  │
│                                                             │
│  ┌──────────┐  ┌───────────────┐                           │
│  │ Workspace│  │ WorkspaceStats│  (v1 scope)               │
│  │ ──────── │  │ ───────────── │                           │
│  │ id (int) │  │ workspace_id  │                           │
│  │ name     │  │ users_count   │                           │
│  │ slug     │  │ messages_count│                           │
│  └──────────┘  └───────────────┘                           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│               Workspace Database (per workspace)            │
│                                                             │
│  ┌──────────┐  ┌──────────────────┐  ┌─────────────┐        │
│  │ Account  │  │ User             │  │ Room        │  ...   │
│  │ ──────── │  │ ──────────────── │  │ ──────────  │        │
│  │ auth_    │  │ workspace_       │  │ name        │        │
│  │  method  │  │   membership_id  │  │ slug        │        │
│  │ settings │  │ email, name, role│  │ type        │        │
│  └──────────┘  └──────────────────┘  └─────────────┘        │
│                                                             │
│  All existing models: Message, Membership, Boost, etc.     │
│  Account = workspace-local settings (auth, permissions)    │
└─────────────────────────────────────────────────────────────┘
```

**Key point**: Each workspace has its own `Account` record. The existing `Account` model continues to work - it just becomes workspace-scoped settings in multi-tenant mode.

### Terminology

| Term | Description | Where |
|------|-------------|-------|
| **Account** | Workspace-local settings (auth method, permissions, branding). Existing model, unchanged. | Each workspace DB |
| **Tenant** | Internal gem term for "isolated database context". Not user-facing. The `activerecord-tenanted` gem uses this. | Code internals |
| **Workspace** | User-facing term for a chat community. What users see and switch between. Registry only (external_id, name, slug). | Untenanted DB |
| **GlobalIdentity** | Global user authentication (email + OTP code). One per person across all workspaces. No name/avatar/password - those are on User. | Untenanted DB |
| **GlobalSession** | Cross-workspace session. Belongs to GlobalIdentity. Stored in untenanted DB. | Untenanted DB |
| **User** | Workspace-specific user record (name, role, avatar). Links to WorkspaceMembership via `workspace_membership_id`. Created when joining a workspace. | Each workspace DB |
| **WorkspaceMembership** | Cross-tenant link between GlobalIdentity and workspace. Stores `global_identity_id` + `tenant` (workspace external_id) + `user_id` (cache). | Untenanted DB |

### Why GlobalIdentity + User Separation? (Fizzy's Pattern)

We adopt Fizzy's pattern (they call it "Identity") of separating GlobalIdentity (global auth) from User (workspace presence):

**1. Database Isolation**
- User stays in workspace DB → all `user_id` FKs are workspace-local
- User links to WorkspaceMembership (untenanted DB), not directly to GlobalIdentity
- GlobalIdentity accessed via `has_one :global_identity, through: :workspace_membership`
- No risk of cross-tenant data leaks via foreign keys

**2. Minimal Code Changes**
- Existing `user_id` references throughout codebase stay unchanged
- Just add `workspace_membership_id` to User model
- Messages, Memberships (room), etc. continue referencing User

**3. Dual-Mode Support**
- Self-hosted: `workspace_membership_id = nil`, User handles auth directly
- Multi-tenant: GlobalIdentity handles auth, User handles workspace presence

**4. WorkspaceMembership as the Cross-Tenant Link**
```
Untenanted DB:                    Tenant DB:
GlobalIdentity                    User
  ↓                                 ↓
WorkspaceMembership ←───────── workspace_membership_id
  (global_identity_id, tenant)
```

**Alternative considered:** Direct `global_identity_id` FK on User. Rejected because:
- Creates cross-DB foreign key (harder to manage)
- WorkspaceMembership pattern allows storing tenant context alongside global_identity

### WorkspaceMembership.user_id Cache

WorkspaceMembership includes a `user_id` column that caches the User's ID from the tenant database:

```
Untenanted DB                         Tenanted DB (per workspace)
┌─────────────────────┐               ┌─────────────────────┐
│ WorkspaceMembership │               │ User                │
│ ─────────────────── │               │ ─────────────────── │
│ id                  │◄──────────────│ workspace_membership_id
│ global_identity_id  │               │ email               │
│ tenant              │               │ name                │
│ user_id (cache) ────│──────────────►│ id                  │
└─────────────────────┘               └─────────────────────┘
```

**Why cache user_id?**
- Performance: Skip `User.find_by(workspace_membership_id:)` on every request
- The cache is populated when User is created, updated if User ID changes (rare)
- No FK constraint enforced (cross-DB), treated as denormalized cache
- Source of truth remains `User.workspace_membership_id`

### Authentication Methods

| Mode | Auth Method | Notes |
|------|-------------|-------|
| Self-hosted | Password OR OTP | Configurable via `Account.auth_method` |
| Multi-tenant MVP | **OTP code only** | No password on GlobalIdentity. Simple, secure. |
| Multi-tenant v2 | OTP + Password + SSO | Add options later |

**MVP Rationale:** OTP-only simplifies GlobalIdentity model (no password_digest), is more secure (no passwords to leak), and matches Fizzy's approach.

### Session Cookies

Different cookie names avoid collision if switching between modes:

| Mode | Cookie Name | Model | Scope |
|------|-------------|-------|-------|
| Self-hosted | `session_token` | `Session` | Single workspace |
| SaaS | `global_session_token` | `GlobalSession` | Cross-workspace |

### OTP Rate Limits

Rate limiting protects against brute-force attacks:

| Scope | Limit | Window |
|-------|-------|--------|
| Per email address | 10 attempts | 3 minutes |
| Per IP address | 20 attempts | 3 minutes |

Higher IP limit accommodates shared networks (offices, VPNs).

### Invite Links and Join Codes

Invite links and join codes are the **same mechanism** - the link simply wraps the code:

```
Join code:    ABCD-EFGH-IJKL
Invite link:  https://campfire.example.com/join?code=ABCD-EFGH-IJKL
Pretty link:  https://campfire.example.com/join/ABCD-EFGH-IJKL
```

Join codes are stored per-workspace via `Account::Joinable` (existing implementation). For fast lookup without querying all tenant DBs, cache join codes in untenanted `Workspace` model.

### First Run Behavior

| Mode | First Run |
|------|-----------|
| Self-hosted | First visitor sees setup wizard (create admin, Account settings) |
| Multi-tenant | No global first run. Root shows combined login/signup. Account auto-created per workspace. |

### Root Route Behavior (SaaS)

No separate marketing page. Combined login/signup flow:

```
GET / (unauthenticated) → Login page with "Enter email"
                          → If email exists: send OTP, verify, login
                          → If email new: create GlobalIdentity, send OTP, verify
GET / (authenticated)   → Redirect to /workspaces (or last workspace)
```

### Workspace Access Denied

When authenticated user visits workspace they're not a member of:

```
GET /1000001/ (not a member) → Redirect to /workspaces
                              → Flash: "You don't have access to this workspace"
```

### User Role Determination

| Action | Role Assigned |
|--------|---------------|
| Create workspace | Administrator |
| Join via code | Member |
| Invited by admin | Member (or role specified in invite, v2) |

Workspaces must always have a creator - no orphan workspaces:

```ruby
class Workspace < UntenantedRecord
  belongs_to :creator, class_name: "GlobalIdentity"
end
```

### Workspace Identification: Path Prefix (like Fizzy)

```
campfire.example.com/                    → Landing page / workspace creation
campfire.example.com/1000001/general     → Workspace 1000001's general room
campfire.example.com/1000002/rooms       → Workspace 1000002's room list
                     └──────┘
                   7+ digit workspace ID
```

**Why path prefix instead of subdomain:**
- No wildcard DNS required
- No wildcard SSL certificate required
- Works with any domain
- Easy local development (no `/etc/hosts` editing)
- Single origin for cookies (simpler auth)

---

## URL Structure

### Path Format
```
/{workspace_id}/{resource}

Examples:
/                           → Landing page (no workspace)
/1000001/                   → Workspace 1000001 root (welcome/chat)
/1000001/general            → Room "general" in workspace 1000001
/1000001/rooms/123/messages → Messages in room 123
/1000001/account/edit       → Workspace settings
/signup                     → Sign up (no workspace context)
/login                      → Login (no workspace context)
```

### Workspace External ID (like Fizzy)

Workspaces use an `external_id` (7+ digit integer) for URLs, generated sequentially:

```ruby
# Workspace model
class Workspace < UntenantedRecord
  before_create :assign_external_id

  def slug
    "/#{external_id}"
  end

  private
    def assign_external_id
      self.external_id ||= ExternalIdSequence.next
    end
end

# Sequential ID with database locking (Fizzy pattern)
class Workspace::ExternalIdSequence < UntenantedRecord
  def self.next
    with_lock do |sequence|
      sequence.increment!(:value).value
    end
  end

  private
    def self.with_lock
      transaction do
        sequence = lock.first_or_create!(value: initial_value)
        yield sequence
      end
    end

    def self.initial_value
      Workspace.maximum(:external_id) || 0
    end
end

# For seeds/fixtures - deterministic IDs from names
external_id = ActiveRecord::FixtureSet.identify("small-bets")
# => 897362094 (7+ digits, deterministic)
```

**URL pattern matching:**
```ruby
PATTERN = /\A(\/\d{7,})(?:/|$)/  # Matches /1234567, /897362094, etc.
```

---

## User Flows

### 1. First-Time Visitor - Sign Up

```
1. User visits campfire.example.com/
2. Sees combined login/signup page: "Enter your email"
3. Enters email address
4. If email not found → GlobalIdentity created
5. OTP code sent to email
6. User enters code → GlobalSession created, cookie set
7. Redirected to /workspaces
   - Shows empty state: "You're not in any workspaces yet"
   - Options: "Create Workspace" or "Join with Code"
```

### 2. User Creates Workspace

```
1. User (with GlobalIdentity) clicks "Create Workspace"
2. Fills form: workspace name
3. Workspace created (ID auto-increments from 1000001)
4. Tenant database created + migrated
5. Account auto-created with defaults:
   - name: workspace name
   - restrict_room_creation_to_administrators: false
   - restrict_direct_messages_to_administrators: false
   - allow_users_to_create_invite_links: true
6. WorkspaceMembership created (creator as global_identity)
7. Redirects to /1000001/
8. User record auto-created from GlobalIdentity (as administrator)
9. Welcome screen: create first room
```

### 3. User Joins Existing Workspace

```
1. User (with GlobalIdentity) has join code or invite link
2. Enters code or clicks link
3. WorkspaceMembership created
4. Redirects to workspace
5. User record auto-created from GlobalIdentity
```

### 4. User Switches Workspace

```
1. User clicks workspace icon in workspace selector
2. Browser navigates to /1000002/
3. Same-origin cookie still valid
4. GlobalSession → GlobalIdentity lookup
5. Find or create User in new workspace from GlobalIdentity
6. User is authenticated in new workspace
```

### 5. Returning User Logs In

```
1. User visits / (unauthenticated)
2. Sees combined login/signup: "Enter your email"
3. Enters email → GlobalIdentity found
4. OTP code sent, user enters code
5. GlobalSession created, cookie set
6. If user has workspaces → redirect to last visited or /workspaces
7. If user has no workspaces → redirect to /workspaces (empty state)
```

### 6. GlobalIdentity Without Workspaces

```
State: User has GlobalIdentity but no WorkspaceMemberships

UI shows:
- "You're not in any workspaces yet"
- "Create Workspace" button
- "Join with Code" input
- User avatar/profile in header (can edit profile, logout)
```

---

## User Lifecycle Details

### When is the User Record Created?

The User record (workspace-scoped) is created **lazily on first workspace access**, not when WorkspaceMembership is created.

```
Timeline:
1. GlobalIdentity created (on signup/login)
2. WorkspaceMembership created (on join/create workspace) - in untenanted DB
3. User navigates to workspace URL (e.g., /1000001/)
4. Authentication middleware sets tenant context
5. ApplicationController finds WorkspaceMembership for this tenant
6. User record created if not exists (with workspace_membership_id FK)
7. Current.user now set, request proceeds
```

**Why lazy creation?**
- WorkspaceMembership is in untenanted DB, can't create User (tenanted) in same transaction
- User record only needed when actually visiting workspace
- Allows pre-creating WorkspaceMemberships (e.g., bulk invites) without tenant context

### User Creation Flow (Detail)

```ruby
# saas/app/controllers/concerns/saas/authentication.rb
module Saas
  module Authentication
    extend ActiveSupport::Concern

    included do
      before_action :set_current_global_session
      before_action :ensure_user_exists_in_workspace, if: -> { Current.workspace && current_workspace_membership }
    end

    private
      def set_current_global_session
        if (token = cookies.signed[:global_session_token])
          Current.global_session = GlobalSession.find_by(token: token)
        end
      end

      def current_workspace_membership
        return unless Current.global_identity && Current.workspace

        @current_workspace_membership ||= Current.global_identity
          .workspace_memberships
          .find_by(tenant: Current.workspace.external_id)
      end

      def ensure_user_exists_in_workspace
        membership = current_workspace_membership
        return if membership.user_id.present?

        # Create User from GlobalIdentity
        user = User.create!(
          workspace_membership_id: membership.id,
          email_address: Current.global_identity.email_address,
          name: Current.global_identity.email_address.split("@").first,
          role: determine_role
        )

        # Update WorkspaceMembership with user_id for faster lookups
        membership.update!(user_id: user.id)
      end

      def determine_role
        # First user in workspace becomes admin
        User.count.zero? ? :administrator : :member
      end
  end
end
```

### User Profile Synchronization (v2)

MVP: Each workspace User has independent name/avatar. No sync.

v2 consideration: Option to sync name/avatar from GlobalIdentity across workspaces.

### Email Changes

When GlobalIdentity email changes:
- MVP: Workspace User emails are independent (set at creation time)
- v2: Option to propagate email change to all workspace Users

---

## Join Codes

Join codes are **per workspace** via the existing `Account` model (each workspace has its own Account).

```ruby
# Existing Account model (workspace-scoped)
class Account < ApplicationRecord
  include Account::Joinable  # Provides join_code functionality
end

# Join flow uses workspace's Account.join_code
# Format: XXXX-XXXX-XXXX (existing implementation)
```

**Join via code flow:**
1. User enters code at `/join` (no workspace context)
2. Look up which workspace has this join code (query all workspaces or use untenanted index)
3. Create WorkspaceMembership linking GlobalIdentity to that workspace
4. Redirect to workspace URL

**Implementation note:** Since join codes are in workspace-scoped Account records, we need either:
- A) Query each workspace DB (slow for many workspaces)
- B) Cache join codes in untenanted Workspace model (denormalized but fast)
- C) Store join codes on Workspace model instead of Account

Recommendation: **Option B** - Add `join_code` column to untenanted `Workspace` model, synced from `Account` on change.

---

## ActionCable Tenant Scoping

The `activerecord-tenanted` gem provides automatic tenant context for ActionCable connections.

### How It Works

```ruby
# saas/app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_tenant

    def connect
      super  # IMPORTANT: Must call super to set tenant context from gem
      self.current_user = find_verified_user
      self.current_tenant = ApplicationRecord.current_tenant
    end

    private
      def find_verified_user
        # Gem has already set tenant context via tenant_resolver
        if Current.workspace_membership&.user
          Current.workspace_membership.user
        else
          reject_unauthorized_connection
        end
      end
  end
end
```

### Stream Types and Tenant Scoping

| Stream Type | Auto-Scoped? | Example |
|-------------|--------------|---------|
| `stream_for model` | Yes | GlobalID includes tenant |
| `stream_from "string"` | No | Must manually prefix |

**GlobalID-based streams (automatic):**
```ruby
# RoomChannel
stream_for @room  # → gid://app/Room/123?tenant=1000001
```

**String-based streams (manual prefixing required):**
```ruby
# Channels using string streams need workspace prefix inline
class PresenceChannel < ApplicationCable::Channel
  def subscribed
    stream_name = Campfire.saas? ? "workspace_#{current_tenant}_presence" : "presence"
    stream_from stream_name
  end
end
```

**Note:** There is no shared `workspace_stream` helper - each channel handles prefixing inline where needed.

### Campfire Channels (All Auto-Scoped)

All Campfire channels use `stream_for` with models, so they're automatically tenant-scoped via GlobalID:

| Channel | Implementation | Tenant-Safe? |
|---------|---------------|--------------|
| `RoomChannel` | `stream_for @room` | Yes (auto) |
| `PresenceChannel` | extends RoomChannel | Yes (auto) |
| `RoomListChannel` | `stream_for Current.account` | Yes (auto) |
| `UserUnreadRoomsChannel` | `stream_for current_user` | Yes (auto) |
| `TypingNotificationsChannel` | `stream_for @room` | Yes (auto) |
| `InboxMentionsChannel` | `stream_for Current.user, :mentions` | Yes (auto) |
| `InboxThreadsChannel` | `stream_for Current.user, :threads` | Yes (auto) |

**No manual tenant prefixing needed** - the gem handles it automatically for all `stream_for` calls.

### Broadcasting

Since all channels use `stream_for`, broadcasting also uses the model-based approach:

```ruby
# Broadcasting to a channel (automatic tenant scoping)
RoomChannel.broadcast_to(@room, data)
UserUnreadRoomsChannel.broadcast_to(user, data)

# Turbo Stream broadcasts (also automatic)
broadcast_append_to @room, :messages, partial: "messages/message"
```

The gem ensures GlobalIDs include the tenant, so broadcasts are automatically scoped.

### Disconnecting Users

```ruby
# When user is removed from workspace
ActionCable.server.remote_connections.where(
  current_tenant: workspace.external_id,
  current_user: user
).disconnect
```

---

## Other Gem Integrations

The `activerecord-tenanted` gem automatically handles tenant scoping for several Rails subsystems.

### Active Storage (Automatic)

The gem automatically includes tenant in blob keys and disk storage paths:

```
# Blob key format: "tenant/ab/cd/abcd12345678"
# Disk path: storage/tenant/ab/cd/abcd12345678
```

No additional configuration needed - file uploads are tenant-isolated by default.

### Active Job (Automatic)

The gem automatically serializes `current_tenant` with job payloads and restores it during `perform`. GlobalID parameters also include tenant. No manual handling required.

### Caching (Manual Scoping Required)

Model cache keys are automatically tenant-scoped:

```ruby
user.cache_key  # => "1000001/users/123-20240101"
```

**Warning:** Direct `Rails.cache` calls require manual scoping:

```ruby
# WRONG - cache key collision across tenants
Rails.cache.fetch("stats") { compute_stats }

# CORRECT - manually include tenant in key
Rails.cache.fetch("#{ApplicationRecord.current_tenant}/stats") { compute_stats }
```

Fragment caching and Russian doll caching work automatically via model cache keys.

---

## MVP Scope

**Note**: MVP implements the SaaS layer (`saas/` folder). Core app continues to work as single-tenant.

### Included

- **SaaS folder structure** - Rails engine with multi-tenancy infrastructure
- **Multi-workspace infrastructure** - Database-per-workspace with activerecord-tenanted gem
- **GlobalIdentity** - Shared GlobalIdentity model, cross-workspace GlobalSessions
- **Workspace selector** - Shows user's workspaces, + button to create new
- **Workspace creation** - Self-service via workspace selector or landing page
- **Landing page** - First-time visitor flow with "Create Workspace" CTA
- **Workspace settings** - Each workspace has its own `Account` for settings
- **All existing features** - Work within workspace context
- **SaaS detection** - `Campfire.saas?` method to conditionally enable multi-tenancy

### Excluded (v1 Scope)

- Super admin authentication
- Admin dashboard
- Workspace management (CRUD, suspend, delete)
- WorkspaceStats aggregation
- Production deployment configs (Kamal, wildcard SSL)
- Security audit

### Core App (Unchanged)

- Existing `Account` model stays as-is
- Single-tenant deployment works without any SaaS components
- No shared database required for core app

---

## Technical Requirements

### Gem

```ruby
# Gemfile.saas
gem "activerecord-tenanted"
```

### Database Configuration

The database configuration in `config/database.yml` uses ERB conditionals to switch between single-tenant and SaaS modes:

```yaml
# config/database.yml (SaaS mode paths shown)
default: &default
  adapter: sqlite3

development:
  primary:
    <<: *default
    database: "storage/workspaces/development/%{tenant}/db/main.sqlite3"
    tenanted: true
    max_connection_pools: 50
  untenanted:
    <<: *default
    database: storage/untenanted/development.sqlite3
    migrations_paths: saas/db/untenanted_migrate

test:
  primary:
    <<: *default
    database: "storage/workspaces/test/%{tenant}/db/main.sqlite3"
    tenanted: true
  untenanted:
    <<: *default
    database: storage/untenanted/test.sqlite3
    migrations_paths: saas/db/untenanted_migrate

production:
  primary:
    <<: *default
    database: "storage/workspaces/production/%{tenant}/db/main.sqlite3"
    tenanted: true
    max_connection_pools: 100
  untenanted:
    <<: *default
    database: storage/untenanted/production.sqlite3
    migrations_paths: saas/db/untenanted_migrate
```

### Model Configuration

```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  tenanted
end

# saas/app/models/untenanted_record.rb
class UntenantedRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :untenanted }
end
```

### Workspace Resolution via Tenant Resolver (Path-Based)

Tenant resolution uses two components:

**1. PathRewriter Middleware** (`saas/config/initializers/tenanting/path_rewriter.rb`):
- Extracts workspace ID from URL path
- Moves workspace prefix from PATH_INFO to SCRIPT_NAME
- This ensures URL helpers generate correct prefixed URLs

**2. Tenant Resolver Lambda** (`saas/config/initializers/tenanting/tenant_resolver.rb`):
- Tells the gem which tenant to use for each request
- Reads from SCRIPT_NAME (already processed by PathRewriter)

```ruby
# saas/config/initializers/tenanting/path_rewriter.rb
class PathRewriter
  WORKSPACE_PATTERN = /\A(\/\d{7,})(?:\/|$)/

  def call(env)
    if env["PATH_INFO"] =~ WORKSPACE_PATTERN
      prefix = $1
      env["SCRIPT_NAME"] = prefix
      env["PATH_INFO"] = env["PATH_INFO"].sub(prefix, "")
      env["PATH_INFO"] = "/" if env["PATH_INFO"].empty?
    end
    @app.call(env)
  end
end

# saas/config/initializers/tenanting/tenant_resolver.rb
Rails.application.config.active_record_tenanted.tenant_resolver = ->(request) do
  if request.script_name =~ /\A\/(\d{7,})\z/
    $1  # Returns workspace external_id as tenant
  end
end

# The gem automatically:
# - Sets ApplicationRecord.current_tenant
# - Wraps request in with_tenant block
# - Handles "no tenant" case for public routes

# Current.workspace is set lazily when accessed (see app/models/current.rb):
class Current < ActiveSupport::CurrentAttributes
  def workspace
    return @workspace if defined?(@workspace)
    @workspace = if ApplicationRecord.current_tenant.present?
      Workspace.find_by(external_id: ApplicationRecord.current_tenant)
    end
  end
end
```

### URL Generation with Workspace Prefix

```ruby
# All URL helpers automatically include SCRIPT_NAME
# which contains the workspace prefix

# In controllers/views:
room_path(@room)           # → /1000001/rooms/123 (automatic)
root_path                  # → /1000001/ (automatic)

# Cross-workspace links need explicit script_name:
root_path(script_name: other_workspace.slug)  # → /1000002/

# Workspace model helper
class Workspace < UntenantedRecord
  def slug
    "/#{external_id}"
  end
end
```

### GlobalIdentity Authentication Flow

```ruby
# Current uses delegates (Fizzy pattern)
class Current < ActiveSupport::CurrentAttributes
  attribute :global_session

  delegate :global_identity, to: :global_session, allow_nil: true

  # Workspace is lazily loaded from tenant context
  def workspace
    return @workspace if defined?(@workspace)
    @workspace = if ApplicationRecord.current_tenant.present?
      Workspace.find_by(external_id: ApplicationRecord.current_tenant)
    end
  end
end

# Authentication concern (saas/app/controllers/concerns/saas/authentication.rb)
def start_new_session_for(global_identity)
  # Create global_session in untenanted DB
  global_session = global_identity.global_sessions.create!(
    user_agent: request.user_agent,
    ip_address: request.remote_ip
  )

  Current.global_session = global_session

  # Set cookie using global_session_token (not session_token)
  cookies.signed.permanent[:global_session_token] = {
    value: global_session.token,
    httponly: true,
    secure: Rails.env.production?,
    same_site: :lax
  }
end

# Access pattern:
#   Current.global_session = GlobalSession.find_by(token: token)
#   Current.global_identity  # → global_session.global_identity (delegate)
#   Current.workspace        # → lazy lookup from ApplicationRecord.current_tenant
```

---

## Workspace Selector Design

Liminal-style design:
- 72px wide sidebar on left
- User avatar at top
- 48px rounded square workspace icons
- Active indicator pill on left edge
- "+" button at bottom for new workspace
- Only shown when user has 2+ workspaces (configurable)

```
┌────┐ ┌─────────────────────────────────┐
│ 👤 │ │                                 │
│────│ │                                 │
│ 🔵 │ │     Main App Content            │
│ ⬜ │ │                                 │
│ ⬜ │ │                                 │
│    │ │                                 │
│    │ │                                 │
│ +  │ │                                 │
└────┘ └─────────────────────────────────┘
```

Workspace links use `slug` to switch workspaces:
```erb
<a href="<%= root_path(script_name: workspace.slug) %>">
  <%= workspace.name %>
</a>
```

---

## Environment Variables

### Required for Multi-Workspace

```bash
# Application host (single domain, no wildcard needed)
APP_HOST=campfire.example.com
```

### Optional

```bash
# Default tenant for development (rails console, etc.)
# Uses gem's ARTENANT env var: ARTENANT=1000001 rails console
# Or configure via: config.active_record_tenanted.default_tenant = "1000001"

# Minimum workspaces to show selector (default: 2)
WORKSPACE_SELECTOR_MIN=1
```

**Note**: No `WORKSPACE_COOKIE_DOMAIN` needed - cookies are same-origin.

---

## Routes Configuration

```ruby
# config/routes.rb

Rails.application.routes.draw do
  # === Public routes (no workspace context) ===
  # Accessed at / without workspace prefix

  # Landing page
  root to: "marketing#show"

  # GlobalIdentity management
  get "signup", to: "registrations#new"
  post "signup", to: "registrations#create"
  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  resource :password_reset, only: [:new, :create, :edit, :update]  # Single-tenant only
  resource :profile, only: [:edit, :update]  # Edit GlobalIdentity (email)

  # Workspace management (requires GlobalIdentity, no workspace)
  get "workspaces", to: "workspaces#index"  # List user's workspaces or empty state
  get "workspaces/new", to: "workspaces#new"  # Create workspace form
  post "workspaces", to: "workspaces#create"  # Create workspace
  get "join", to: "workspaces#join"  # Join with code form
  post "join", to: "workspaces#join_with_code"  # Process join code

  # === Workspace routes (with /{workspace_id}/ prefix) ===
  # Middleware strips prefix and sets SCRIPT_NAME
  # All routes below work as normal but are "mounted" at /{workspace_id}/

  # Room routes (workspace-scoped)
  resources :rooms do
    resources :messages
    # ... etc
  end

  # Workspace settings (workspace-scoped, admin only)
  resource :account, only: [:show, :edit, :update]

  # ... all existing routes
end
```

---

## Testing Strategy

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  # Gem automatically sets default tenant from config.active_record_tenanted.default_tenant
  # No manual setup needed - gem handles this
end

class ActionDispatch::IntegrationTest
  # Integration tests use path prefix
  def workspace_path(path, workspace_id: 1000001)
    "/#{workspace_id}#{path}"
  end

  # Example usage:
  # get workspace_path("/rooms")  # → GET /1000001/rooms
end
```

---

## Open Source & SaaS Separation

The multi-tenancy code lives in the `saas/` folder, keeping the core app clean for single-tenant self-hosters.

### Structure (like Fizzy)

```
campfire/
├── app/                      # Core open-source app
├── config/
├── db/
├── Gemfile                   # Core dependencies (SQLite, etc.)
├── Gemfile.saas              # SaaS dependencies (extends Gemfile)
├── LICENSE                   # O'Saasy or similar license
└── saas/                     # SaaS-only code (Rails engine)
    ├── app/
    │   ├── controllers/      # Admin dashboards, billing
    │   ├── models/           # Subscriptions, plans, billing
    │   └── views/            # SaaS-specific UI
    ├── lib/campfire/saas/
    │   └── engine.rb         # Rails engine setup
    ├── config/routes.rb      # SaaS routes (admin namespace)
    ├── db/saas_schema.rb     # SaaS-only tables
    └── campfire-saas.gemspec # Packaged as gem
```

### SaaS Detection

```ruby
# lib/campfire.rb
module Campfire
  def self.saas?
    return @saas if defined?(@saas)
    @saas = ENV["SAAS"] == "true" || File.exist?(Rails.root.join("tmp/saas.txt"))
  end
end

# Usage in code
if Campfire.saas?
  # SaaS-only feature
end
```

### Dual Gemfile

```ruby
# Gemfile.saas
eval_gemfile "Gemfile"  # Inherit core gems

gem "campfire-saas", path: "saas"
gem "stripe"           # Billing
gem "sentry-ruby"      # Error tracking
# ... other SaaS dependencies
```

### Rake Tasks

```bash
bin/rails saas:enable   # Creates tmp/saas.txt
bin/rails saas:disable  # Removes tmp/saas.txt
```

### License

**O'Saasy License** (or similar):
- Free to use, modify, and self-host
- Cannot offer as SaaS to third parties
- Protects open-source from SaaS competition

### What Goes Where

| Component | Core (open-source) | SaaS folder |
|-----------|-------------------|-------------|
| Account model (settings) | Yes | - |
| User, Room, Message, etc. | Yes | - |
| Single-tenant auth (Session) | Yes | - |
| Multi-tenancy infrastructure | - | Yes |
| GlobalIdentity (cross-workspace auth) | - | Yes |
| Workspace model & selector | - | Yes |
| Tenant resolver (lambda) | - | Yes |
| Untenanted database config | - | Yes |
| Admin dashboard | - | Yes |
| Billing/Stripe | - | Yes (v2+) |
| Usage limits | - | Yes (v2+) |
| Super admin | - | Yes (v1) |

### Implementation Order

1. **MVP**: SaaS folder structure + multi-workspace infrastructure (this PRD)
2. **v1**: Admin dashboard, workspace management, super admin
3. **v2**: Billing, usage limits, advanced features
   - Global user settings on GlobalIdentity (cross-workspace preferences)
   - Profile sync across workspaces (name/avatar from GlobalIdentity)
   - SSO integration

---

## Migration from Single-Workspace

Not supported. This is a clean implementation for new deployments only.

Existing single-workspace Campfire deployments should:
1. Export their data
2. Deploy fresh multi-workspace instance
3. Import data to a new workspace

---

## Data Portability (v2)

The SQLite-per-workspace architecture is designed to support data portability - workspaces migrating between multi-tenant SaaS and self-hosted deployments. Implementation deferred to v2.

**Key considerations for v2:**
- Export (workspace → self-hosted): Straightforward file copy, minor schema differences
- Import (self-hosted → workspace): Requires migration tooling and user re-authentication
- Authentication model transition: Password auth → GlobalIdentity OTP

---

## References

- [activerecord-tenanted gem](https://github.com/basecamp/activerecord-tenanted)
- [Fizzy's path-based workspaceing](./multitenant-saas-notes.md)
- [Rails Multiple Databases Guide](https://guides.rubyonrails.org/active_record_multiple_databases.html)
