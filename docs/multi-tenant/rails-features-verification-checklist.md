# Rails Features Verification Checklist

Verify all Rails features work correctly in both modes:
- **SaaS mode**: With tenant context (`ApplicationRecord.current_tenant` set)
- **Self-hosted mode**: Without tenant context (single database)

## Legend
- [ ] Not tested
- [x] Verified working
- ⚠️ Known issue / needs fix

---

## 1. CurrentAttributes

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `Current.user` | [x] | [x] | SaaS: via workspace_membership, Self-hosted: direct attribute |
| `Current.global_session` | [x] | N/A | SaaS only - set in `Saas::Authentication` and core `Authentication` (when `Campfire.saas?`) |
| `Current.global_identity` | [x] | N/A | SaaS only - delegates to `global_session.global_identity` |
| `Current.workspace_membership` | [x] | N/A | SaaS only - auto-set in `global_session=` setter |
| `Current.workspace` | [x] | [x] | Returns nil in self-hosted; lazy-loads Workspace in SaaS |
| `Current.account` | [x] | [x] | Uses `Account.sole` in both modes |
| Request metadata (ip, user_agent, etc.) | [x] | [x] | Available via `Current.request`; session also stores ip/user_agent |
| Reset between requests | [x] | [x] | `reset` method clears @workspace, @account |
| Thread isolation | [x] | [x] | Via ActiveSupport::CurrentAttributes |

**Implementation:** `app/models/current.rb`

**Status:** `Current.reset` called in both test helpers (self-hosted and SaaS)

---

## 2. Active Job

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Job enqueue with tenant | [x] | N/A | Gem captures tenant in `initialize` |
| Job perform in correct tenant | [x] | N/A | Gem wraps `perform_now` with `with_tenant` |
| GlobalID serialization | [x] | [x] | Gem adds `?tenant=` param to GID |
| `perform_later` | [x] | [x] | Tenant serialized in job data |
| `perform_now` | [x] | [x] | Tenant context restored from serialized data |
| Mailer `deliver_later` | [x] | [x] | Gem provides mailer module integration |
| Job without tenant context | N/A | [x] | Works when gem loaded but tenant is nil |

**Implementation:** `activerecord-tenanted` gem at `lib/active_record/tenanted/job.rb`

**Key Pattern:** Jobs like `UnreadMentionsNotifierJob` show dual-mode pattern:
```ruby
def perform
  if Campfire.saas?
    ApplicationRecord.with_each_tenant { notify_users_in_current_workspace }
  else
    notify_users_in_current_workspace
  end
end
```

---

## 3. Action Cable

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Channel subscription | [x] | [x] | Gem wraps commands with `around_command :with_tenant` |
| Broadcast to channel | [x] | [x] | Streams auto-scoped via GlobalID tenant param |
| `stream_for` with model | [x] | [x] | GlobalID includes tenant automatically |
| Connection authentication | [x] | [x] | SaaS: GlobalSession→User, Self-hosted: Session→User |
| Disconnect | [x] | [x] | Standard ActionCable behavior |
| Multiple tenants same user | [x] | N/A | Different connections per workspace |

**Campfire channels verified:**
- [x] `RoomChannel` - `stream_for @room` (model-based stream, tenant-safe via GlobalID)
- [x] `PresenceChannel` - Inherits `RoomChannel` (model-based stream)
- [x] `RoomListChannel` - `stream_for Current.account` (model-based stream)
- [x] `UserUnreadRoomsChannel` - `stream_for current_user` (model-based stream)
- [x] `TypingNotificationsChannel` - `stream_for @room` (model-based stream)
- [x] `InboxMentionsChannel` - `stream_for current_user`
- [x] `InboxThreadsChannel` - `stream_for current_user`
- [x] `InboxBookmarksChannel` - `stream_for current_user`
- [x] `UnreadNotificationsChannel` - `stream_for current_user`
- [x] `UserInvolvementsChannel` - `stream_for current_user`
- [x] `ReadRoomsChannel` - `stream_for current_user`
- [x] `HeartbeatChannel` - No tenant data access; standard channel

**Implementation:**
- Connection: `app/channels/application_cable/connection.rb` (dual-mode connect)
- Tenant context: `saas/app/channels/concerns/tenant_context.rb`
- ActionCable URL helper: `saas/app/helpers/tenanting_helper.rb#tenanted_action_cable_meta_tag`

**Note:** All channels use model-based streams (`stream_for`). These use GlobalID under the hood, and the
`activerecord-tenanted` gem automatically scopes GlobalIDs with `?tenant=...`, so streams are tenant-safe
without string-based `workspace_stream` prefixes.

---

## 4. Turbo Streams

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `turbo_stream_from` | [x] | [x] | Model-based streams use GlobalID with tenant param |
| `broadcast_append_to` | [x] | [x] | Used in `Message::Broadcasts` concern |
| `broadcast_replace_to` | [x] | [x] | Used in jobs and controllers |
| `broadcast_remove_to` | [x] | [x] | Used in `Message::Broadcasts` |
| Broadcasts from background jobs | [x] | [x] | Falls back to `ApplicationRecord.current_tenant` |
| Turbo Frame requests | [x] | [x] | Standard Turbo behavior |

**Implementation:** `saas/config/initializers/tenanting/turbo.rb`

```ruby
module TurboStreamsChannelExtensions
  class_methods do
    def render_format(format, **rendering)
      script_name = resolve_tenant_script_name
      if script_name.present?
        ApplicationController.renderer.new(script_name: script_name).render(formats: [ format ], **rendering)
      else
        super
      end
    end

    private

    def resolve_tenant_script_name
      # Prefer Current.workspace (request context)
      # Fall back to ApplicationRecord.current_tenant (job context)
      if Current.workspace.present?
        Current.workspace.slug
      elsif ApplicationRecord.current_tenant.present?
        "/#{ApplicationRecord.current_tenant}"
      end
    end
  end
end
```

---

## 5. Active Storage

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| File upload | [x] | [x] | Standard Active Storage |
| File download URL | [x] | [x] | `script_name` injected via before_action |
| Direct upload | [x] | [x] | With tenant prefix in URL |
| Variants/previews | [x] | [x] | Proxy mode maintains tenant context |
| Blob key includes tenant | [x] | N/A | Gem handles blob key prefixing |
| Disk service path | [x] | [x] | Blob metadata stored per-tenant in DB; disk root is shared (see `config/storage.yml`) |

**Implementation:** `saas/config/initializers/tenanting/active_storage.rb`

```ruby
# Uses proxy mode (serves through Rails, maintains tenant context)
Rails.application.config.active_storage.resolve_model_to_route = :rails_storage_proxy

# Sets URL options with script_name
def set_active_storage_url_options
  ActiveStorage::Current.url_options = {
    protocol: request.protocol, host: request.host,
    port: request.port, script_name: request.script_name
  }
end
```

---

## 6. Action Mailer

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Send email | [x] | [x] | Standard ActionMailer |
| `deliver_later` | [x] | [x] | Uses Active Job (tenant preserved) |
| URL generation in emails | [x] | [x] | Gem interpolates tenant into URL options |
| Mailer previews | [x] | [x] | Standard Rails previews |

**SaaS Mailers:**
- `AuthCodeMailer` - OTP codes for authentication (uses untenanted GlobalIdentity)

**Self-Hosted Mailers:**
- `AuthTokenMailer` - OTP codes
- Standard user/message notification mailers

---

## 7. Caching

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Fragment caching | [x] | [x] | Gem auto-prepends tenant to cache keys |
| Russian doll caching | [x] | [x] | Works via tenant-aware `cache_key` |
| `cache_key` on models | [x] | [x] | Gem overrides to include tenant prefix |
| SQL query cache | [x] | [x] | Per connection pool (auto-isolated) |
| Rails.cache direct access | [x] | [x] | Scoped via tenant-aware keys (e.g., `tenant_cache_key`, `active_member_count_cache_key`) |
| Collection caching | [x] | [x] | Uses model cache keys (tenant-aware) |

**Cache key format:**
```ruby
# SaaS: "1000001/users/123-20240101"
# Self-hosted: "users/123-20240101"
user.cache_key
```

**⚠️ Warning:** Direct `Rails.cache` calls require manual tenant scoping. Document this in PRD but no linting guard exists.

**Intentionally Global Cache:** `User::DicebearAvatar` uses global cache key (external CDN resource, not per-tenant)

---

## 8. GlobalID

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `to_global_id` | [x] | [x] | Gem adds `?tenant=` param |
| `to_signed_global_id` | [x] | [x] | Same tenant handling |
| `GlobalID::Locator.locate` | [x] | [x] | Gem provides custom locator with tenant validation |
| GlobalID in Active Job | [x] | [x] | Tenant preserved in job arguments |
| GlobalID in Action Cable | [x] | [x] | Stream names are tenant-aware |

**Format:**
```ruby
# SaaS: gid://campfire-ce/User/123?tenant=1000001
# Self-hosted: gid://campfire-ce/User/123
user.to_global_id
```

**Implementation:** `activerecord-tenanted` gem at `lib/active_record/tenanted/global_id.rb`

**Locator Safety:**
- Raises `MissingTenantError` if tenant not in GID
- Raises `NoTenantError` if locating without tenant context
- Raises `WrongTenantError` if GID tenant doesn't match current

---

## 9. Database Operations

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `ApplicationRecord.with_tenant` | [x] | N/A | Block-scoped tenant switching |
| `ApplicationRecord.current_tenant` | [x] | N/A | Returns current tenant ID |
| Cross-tenant query prevention | [x] | N/A | Raises `NoTenantError` without context |
| `disable_joins: true` associations | [x] | N/A | Used for cross-DB relations |
| Untenanted models (GlobalIdentity, etc.) | [x] | N/A | `UntenantedRecord` base class |
| Connection pool management | [x] | N/A | LRU reaping via `max_connection_pools` config |
| Migrations | [x] | [x] | `db:migrate` runs for all tenants |

**Implementation:** `app/models/application_record.rb`
```ruby
tenanted if defined?(ActiveRecord::Tenanted) && Campfire.saas?
```

**Database Configuration:** `saas/config/database.yml.saas`
```yaml
primary:
  database: storage/workspaces/%{tenant}/db/main.sqlite3
  tenanted: true
  max_connection_pools: 50  # LRU reaping
untenanted:
  database: storage/untenanted/development.sqlite3
```

---

## 10. Testing

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Unit tests with fixtures | [x] | [x] | Default tenant from config (ARTENANT/initializer) |
| Integration tests | [x] | [x] | Workspace-scoped request helpers (path-prefixed) |
| System tests | [ ] | [x] | No SaaS system test helper yet |
| `without_tenant` helper | [x] | N/A | For untenanted operations in tests |
| Parallel test suite | [x] | [x] | Unique tenant per worker |
| Creating tenants in tests | [x] | N/A | Allowed in transactional tests |

**SaaS Test Helper:** `saas/test/test_helper.rb`
- Default tenant: `ARTENANT=1000001`
- Fixture loading from `saas/test/fixtures/`
- Integration helpers: `workspace_get`, `workspace_post`, etc.

---

## 11. Console

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Default tenant in dev | [x] | N/A | `config.active_record_tenanted.default_tenant` |
| `ARTENANT` env var | [x] | N/A | Override default tenant |
| Switch tenant in console | [x] | N/A | `ApplicationRecord.current_tenant = "1000001"` |
| Untenanted access | [x] | N/A | GlobalIdentity, GlobalSession accessible always |

**Configuration:** `saas/config/initializers/tenanting/default_tenant.rb`

---

## 12. URL Generation

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `root_path` | [x] | [x] | Returns `/` (relative to script_name) |
| `root_url` | [x] | [x] | Includes full URL with tenant prefix |
| Named routes | [x] | [x] | Auto-include script_name |
| `script_name` in URLs | [x] | N/A | PathRewriter middleware handles |
| Redirect URLs | [x] | [x] | Controllers use workspace prefix |
| `url_for` with tenant | [x] | [x] | Standard Rails behavior |

**Untenanted URL Helpers:** `saas/app/helpers/tenanting_helper.rb`
```ruby
def untenanted_url(route_name, *args)
  url_options = { script_name: "", host: request.host, ... }
  Rails.application.routes.url_helpers.public_send(:"#{route_name}_url", *args, **url_options)
end
```

---

## 13. Authentication Flow

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Login (before tenant) | [x] | [x] | SaaS: untenanted routes, Self-hosted: normal |
| Workspace selection | [x] | N/A | `Saas::WorkspacesController#index` |
| Session cookie | [x] | [x] | SaaS: `:global_session_token`, Self-hosted: `:session_token` |
| Auth code flow | [x] | N/A | 6-char OTP via `AuthCode` model |
| Password auth | N/A | [x] | Via `User.authenticate_by` |
| Return URL after login | [x] | [x] | `safe_redirect_url?` validation |

**Session Cookie Differences:**
| Aspect | SaaS | Self-Hosted |
|--------|------|-------------|
| Cookie name | `:global_session_token` | `:session_token` |
| Database | Untenanted (GlobalSession) | Tenanted (Session) |
| Scope | Cross-workspace | Single workspace |
| Lifetime | 30 days | 30 days |

**Implementation:**
- SaaS: `saas/app/controllers/concerns/saas/authentication.rb`
- Self-hosted: `app/controllers/concerns/authentication.rb`

---

## 14. Logging

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Tenant in SQL logs | [x] | N/A | `[tenant=1000001]` via gem |
| Tenant in Rails.logger | [x] | N/A | Tagged logging |
| Request ID tracking | [x] | [x] | Via CurrentRequest concern |
| Structured logging | [x] | [x] | Standard Rails logging |

**Implementation:** `saas/config/initializers/tenanting/logging.rb`
- SQL query tags: `/*tenant:1000001*/`
- Controller around_action: `tag_logs_with_tenant`

---

## 15. Error Handling

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `TenantDoesNotExistError` → 404 | [x] | N/A | Mapped to 404 via gem rescue responses |
| `NoTenantError` handling | [x] | N/A | Gem raises when accessing DB without tenant |
| `WrongTenantError` handling | [x] | N/A | Via authentication layer validation |
| Error pages with tenant context | [x] | [x] | TenantSelector raises `TenantDoesNotExistError` → 404 |

**⚠️ Known Gap:** No explicit application-level 404 handling when PathRewriter extracts invalid workspace ID. Currently handled at model level via rescue blocks.

---

## 16. Multi-Tenancy Core

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `ApplicationRecord.tenanted` macro | [x] | N/A | Conditionally applied in ApplicationRecord |
| `ApplicationRecord.current_tenant` | [x] | N/A | Returns current tenant ID string |
| `ApplicationRecord.with_tenant(id)` | [x] | N/A | Block-scoped tenant switch |
| `ApplicationRecord.with_each_tenant` | [x] | N/A | Iterates all tenants |
| `ApplicationRecord.without_tenant` | [x] | N/A | For untenanted operations |
| `ApplicationRecord.tenant_exist?(id)` | [x] | N/A | Checks if tenant DB exists |
| `ApplicationRecord.create_tenant(id)` | [x] | N/A | Creates tenant DB + migrates |
| `ApplicationRecord.destroy_tenant(id)` | [x] | N/A | Drops tenant DB |
| `model.tenant` attribute | [x] | N/A | Readonly, returns tenant ID |

**Implementation:** `activerecord-tenanted` gem provides all these via the `tenanted` macro.

---

## 17. Tenant Isolation

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Query without tenant raises error | [x] | N/A | `NoTenantError` |
| Model from wrong tenant raises error | [x] | N/A | `WrongTenantError` via GlobalID locator |
| Cannot save model in wrong tenant | [x] | N/A | Gem validates tenant context |
| Cross-tenant association blocked | [x] | N/A | Unless `disable_joins: true` |
| Fixtures isolated per tenant | [x] | N/A | Each tenant has own DB |
| Parallel tests get unique tenants | [x] | N/A | Worker-specific tenant ID |

**Multi-layer Defense:**
1. Database isolation (separate SQLite files per workspace)
2. Middleware validation (7+ digit workspace ID pattern)
3. Authentication validation (`workspace_accessible?` check)
4. Query context (`with_tenant` blocks)
5. Association scoping (`disable_joins: true`)

---

## 18. Untenanted Models

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `UntenantedRecord` base class | [x] | N/A | `connects_to database: :untenanted` |
| GlobalIdentity model accessible | [x] | N/A | Cross-workspace identity |
| GlobalSession model accessible | [x] | N/A | Cross-workspace session |
| WorkspaceMembership model accessible | [x] | N/A | Links identity to workspace |
| Workspace model accessible | [x] | N/A | Workspace registry |
| AuthCode model accessible | [x] | N/A | OTP codes for auth |
| Cross-DB associations work | [x] | N/A | `disable_joins: true` pattern |

**Implementation:** `saas/app/models/untenanted_record.rb`
```ruby
class UntenantedRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :untenanted, reading: :untenanted }
end
```

---

## 19. Tenant Resolution (Path-Based)

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `/1000001/rooms` → tenant 1000001 | [x] | N/A | PathRewriter extracts 7+ digit ID |
| `SCRIPT_NAME` set correctly | [x] | N/A | `/1000001` moved to SCRIPT_NAME |
| `PATH_INFO` stripped of tenant | [x] | N/A | Becomes `/rooms` |
| URL helpers include tenant prefix | [x] | N/A | Auto via script_name |
| Redirect URLs include tenant | [x] | N/A | Controllers use `/#{workspace.external_id}` |
| Invalid tenant → 404 | [x] | N/A | TenantSelector raises `TenantDoesNotExistError` → 404 |
| No tenant in path → untenanted | [x] | N/A | SaaS routes match |

**Implementation:** `saas/lib/campfire/saas/path_rewriter.rb`
```ruby
PATH_INFO_MATCH = %r{\A(/(\d{7,}))(/.*)?\z}
# Extracts workspace ID, rewrites SCRIPT_NAME/PATH_INFO
```

---

## 20. Workspace Lifecycle

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| Create workspace | [x] | N/A | `Workspace.create_with_database!` |
| Workspace has unique external_id | [x] | N/A | 7+ digit via `ExternalIdSequence` |
| First user becomes administrator | [x] | N/A | Created with `:administrator` role |
| Join via code creates workspace_membership | [x] | N/A | `WorkspacesController#join` |
| User deactivation in workspace | [x] | [x] | Soft delete via `Deactivatable` concern |
| Workspace suspension | [x] | N/A | `suspended_at` timestamp |

**Workspace Creation Flow:**
1. Create Workspace record in untenanted DB
2. Assign external_id
3. Create tenant database via `ApplicationRecord.create_tenant`
4. Create WorkspaceMembership for creator
5. Switch to tenant, create Account singleton
6. Create admin User, link to WorkspaceMembership
7. Create default "General" room

---

## 21. GlobalIdentity & Authentication (SaaS)

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| GlobalIdentity created on first login | [x] | N/A | Via `RegistrationsController` |
| Auth code sent to email | [x] | N/A | 6-char OTP via `AuthCodeMailer` |
| Code sanitization (O→0, I→1, L→1) | [x] | N/A | `OtpCode` module |
| GlobalSession created on code verify | [x] | N/A | `AuthCodesController#create` |
| GlobalSession cookie set (httponly) | [x] | N/A | `signed.permanent` cookie |
| WorkspaceMembership auto-created on join | [x] | N/A | `WorkspacesController#join` |
| User created on workspace entry | [x] | N/A | `ensure_workspace_user_exists` |
| `Current.global_session` → `Current.global_identity` | [x] | N/A | Delegate method |
| `Current.workspace_membership` set from tenant | [x] | N/A | In `global_session=` setter |
| `Current.user` derived correctly | [x] | N/A | `workspace_membership.user` |

**Implementation:**
- Models: `saas/app/models/global_identity.rb`, `global_session.rb`, `workspace_membership.rb`, `auth_code.rb`
- Controllers: `saas/app/controllers/saas/sessions_controller.rb`, `auth_codes_controller.rb`, `registrations_controller.rb`

---

## 22. Testing Infrastructure

| Feature | SaaS Mode | Self-Hosted | Notes |
|---------|-----------|-------------|-------|
| `default_tenant` configured | [x] | N/A | `ARTENANT=1000001` via initializer default |
| Unit tests run in tenant context | [x] | [x] | Gem sets automatically |
| Integration tests set `script_name` | [x] | N/A | Helpers prefix paths (no explicit `script_name`) |
| System tests set `script_name` | [ ] | N/A | No SaaS system test helper yet |
| `without_tenant` helper works | [x] | N/A | For untenanted operations |
| Parallel tests isolated | [x] | [x] | Unique tenant per worker |
| Fixtures load in tenant DB | [x] | [x] | Gem handles fixture loading |
| SaaS fixtures separate | [x] | N/A | `saas/test/fixtures/` |
| Both modes run in CI | [x] | [x] | `bin/rails test && SAAS=true bin/rails test saas/test/` |

**Test Helper:** `saas/test/test_helper.rb`
- Sign-in helpers: `sign_in_global_identity`
- Cookie helpers: `set_global_session_cookie`
- Request helpers: `workspace_get`, `workspace_post`, etc.
- Fixture accessors for untenanted models

---

## 23. Self-Hosted Viability (Non-Tenanted Mode)

Verify self-hosters can deploy Campfire on their own domain without multi-tenancy.

### Architecture Separation

| Component | Self-Hosted | SaaS | Conflict? |
|-----------|-------------|------|-----------|
| Gemfile | Base `Gemfile` | `Gemfile.saas` (extends base) | [x] None |
| `activerecord-tenanted` gem | Not installed | Installed | [x] None |
| `campfire-saas` engine | Not loaded | Loaded | [x] None |
| Database | Single SQLite | Tenant DBs + untenanted | [x] None |
| Authentication | Password/OTP | Magic link | [x] Separate routes |
| Domain | Any (`chat.company.com`) | Path-based (`/1000001/`) | [x] Independent |

### Core App Conditionals

| Change | Self-Hosted Behavior | Verified? |
|--------|---------------------|-----------|
| `Campfire.saas?` | Returns `false` | [x] |
| `Current.user` | Uses direct attribute (existing behavior) | [x] |
| `Current.workspace` | Returns `nil` | [x] |
| `Current.global_session` | Not used (nil) | [x] |
| `User.workspace_membership` | Always `nil` (optional association) | [x] |
| `workspace_membership_id` column | Always `null` | [x] |

### Self-Hosted Deployment Checklist

| Feature | Status | Notes |
|---------|--------|-------|
| Fresh install with base Gemfile | [x] | No SaaS gems |
| First-run setup flow | [x] | Creates Account + Admin user |
| Password authentication | [x] | Existing flow unchanged |
| OTP authentication (if enabled) | [x] | Per-account setting |
| Single Account model | [x] | `Account.sole` |
| All rooms accessible | [x] | No tenant scoping |
| File uploads work | [x] | Standard Active Storage |
| ActionCable works | [x] | No tenant in streams |
| Background jobs work | [x] | No tenant context |
| Email notifications work | [x] | Standard mailer URLs |
| Custom domain | [x] | Any domain works |
| Docker deployment | [x] | Existing Dockerfile |
| Kamal deployment | [x] | Existing config |

### Migration Safety

| Migration | Self-Hosted Impact | Verified? |
|-----------|-------------------|-----------|
| `add_workspace_membership_id_to_users` | Column is `null: true`, always nil | [x] |
| No other schema changes | Core tables unchanged | [x] |

### Code Guard Pattern

All SaaS-specific code must use this pattern:

```ruby
# CORRECT - guarded
if Campfire.saas?
  # SaaS-only code
end

# CORRECT - dual-mode method
def user
  if Campfire.saas? && workspace_membership
    workspace_membership.user
  else
    super  # Self-hosted path
  end
end

# WRONG - would break self-hosted
ApplicationRecord.current_tenant  # NoMethodError if gem not loaded
```

### Required Core File

```ruby
# lib/campfire.rb (MUST be in core app, not just saas/)
module Campfire
  SAAS_MARKER = File.expand_path("../tmp/saas.txt", __dir__)

  def self.saas?
    return @saas if defined?(@saas)
    @saas = (ENV["SAAS"] == "true" || File.exist?(SAAS_MARKER)) && ENV["SAAS"] != "false"
  end
end
```

### End-to-End Self-Hosted Test

- [x] Clone fresh repo
- [x] `bundle install` (base Gemfile only)
- [x] `bin/rails db:setup`
- [x] `bin/rails server`
- [x] Complete first-run setup
- [x] Create room, send message
- [x] Invite user, they join
- [x] File upload works
- [x] Real-time updates work
- [ ] Deploy to production server

---

## Test Matrix

### Critical Paths to Test

1. **New user signup (SaaS)**
   - [x] Create global_identity → Send auth code → Verify → Create workspace → Land in workspace

2. **Existing user login (SaaS)**
   - [x] Enter email → Auth code → Verify → Workspace selector → Enter workspace

3. **Join workspace via code (SaaS)**
   - [x] Visit join link → Enter email → Auth code → Land in workspace

4. **Send message with notification**
   - [x] Post message → Job enqueued → Notification delivered → Turbo broadcast

5. **File upload and view**
   - [x] Upload attachment → View in message → Direct download link works

6. **Real-time updates**
   - [x] User A posts → User B sees via Turbo Stream → Presence updates

7. **Background job with model**
   - [x] Enqueue job with Message → Job runs in correct tenant → Message found

8. **Self-hosted single user**
   - [x] First run setup → Password login → Full functionality

---

## Known Issues & Recommendations

### ✅ Issues to Address

No known issues currently tracked in this checklist.

### ✅ Implemented & Working

- All CurrentAttributes for dual-mode operation
- Active Job tenant serialization/restoration
- All 12 ActionCable channels with tenant-aware streams
- Turbo Streams with script_name fix (request + job context)
- Active Storage proxy mode with URL options
- Caching with tenant-prefixed keys
- GlobalID with tenant parameter
- Database isolation and connection pooling
- Authentication flows for both modes
- URL generation and tenant resolution
- Testing infrastructure for both modes

---

## Notes

- Run full test suite: `bin/rails test` (self-hosted) and `SAAS=true bin/rails test saas/test/` (SaaS)
- SaaS system tests not yet implemented
- Pay special attention to jobs and broadcasts (most common issues)
- Check browser console for WebSocket errors
- Verify no tenant leakage in logs between requests
