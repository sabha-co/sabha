# Multi-Tenancy & SaaS Architecture Notes

Comparison of approaches between Fizzy (37signals) and Campfire-CE.

**Related Documents:**
- [Product PRD](./multi-tenancy-product-prd.md) - Business goals, user stories, requirements
- [Technical PRD](./multi-tenancy-technical-prd.md) - Architecture and requirements
- [Implementation Tasks](./multi-tenancy-plans-and-tasks.md) - Task breakdown
- [User Flows](./multi-tenant-user-flows.md) - Detailed user journeys

---

## Key Decision: Identity + User Pattern (Fizzy's Approach)

**Decision:** Adopt Fizzy's Identity + User separation for multi-tenant mode.

### Why This Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│ Untenanted DB (storage/untenanted/{env}.sqlite3)                │
│ ┌─────────────┐                                                 │
│ │ GlobalIdentity │ email (OTP-only, no password for MVP)        │
│ │                │ "Can this person authenticate?"              │
│ └─────────────┘                                                 │
│ ┌─────────────┐                                                 │
│ │ WorkspaceMembership │ global_identity_id, tenant (string)     │
│ │                     │ "Which workspaces can they access?"     │
│ └─────────────┘                                                 │
└─────────────────────────────────────────────────────────────────┘
                    │
                    │ workspace_membership_id (links to untenanted WorkspaceMembership)
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ Workspace DB (storage/workspaces/{env}/{id}/db/main.sqlite3)    │
│ ┌─────────────┐                                                 │
│ │    User     │ name, role, avatar, workspace_membership_id     │
│ │             │ "What can this person do here?"                 │
│ └─────────────┘   (gets identity via has_one :through)          │
│       ↑                                                         │
│       │ user_id (all FKs stay in same DB!)                      │
│ ┌─────┴───────────────────────────────────────────────┐        │
│ │ Messages, Memberships, Rooms, Notifications, etc.   │        │
│ └─────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

### Reasons for This Decision

1. **Fits database-per-workspace architecture**
   - User links to WorkspaceMembership (untenanted DB), not GlobalIdentity directly
   - GlobalIdentity accessed via `has_one :global_identity, through: :workspace_membership`
   - All existing `user_id` FKs stay within workspace DB
   - Works cleanly with separate SQLite files

2. **Minimal changes to existing Campfire code**
   - Just add `workspace_membership_id` to User model
   - All existing associations stay the same
   - No need to add `workspace_id` to every model

3. **Clean data isolation**
   - `user_id` is automatically workspace-scoped
   - No risk of cross-tenant data leaks via FKs

4. **SSO across workspaces**
   - One Identity → many Users (one per workspace)
   - Single login works for all workspaces

### Dual-Mode Support

| Mode | Authentication On | Session Belongs To | WorkspaceMembership Used? |
|------|-------------------|-------------------|---------------------------|
| Self-hosted | User | User | No (`workspace_membership_id = nil`) |
| Multi-tenant | GlobalIdentity | GlobalIdentity (GlobalSession) | Yes (links to WorkspaceMembership) |

```ruby
# Self-hosted: User handles everything (current Campfire behavior)
# Multi-tenant: GlobalIdentity handles auth, WorkspaceMembership links to tenant, User handles workspace presence

class User < ApplicationRecord
  belongs_to :workspace_membership, optional: true  # nil for self-hosted mode
  has_one :global_identity, through: :workspace_membership, disable_joins: true

  # Existing password/auth stays for self-hosted fallback
  has_secure_password validations: false
  has_many :sessions  # For self-hosted mode (core Session, not GlobalSession)
end
```

### Models Summary

**Untenanted DB (multi-tenant only):**
- `GlobalIdentity` - email (no password for MVP - OTP only), has_many :auth_codes, :global_sessions, :workspace_memberships
- `AuthCode` - code, global_identity_id, purpose (sign_in/sign_up/email_change), expires_at
- `GlobalSession` - token, global_identity_id, user_agent, ip_address
- `WorkspaceMembership` - global_identity_id, tenant (string - workspace external_id), user_id (cached)
- `Workspace` - external_id, name, creator_id, suspended_at

**Note:** The `Workspace` model is a registry in the untenanted DB. Per-tenant `Account` model holds workspace settings.

**Workspace DB (always):**
- `Account` - auth_method, settings JSON (workspace-local settings), external_id (7+ digit)
- `User` - name, role, avatar, workspace_membership_id (nullable), + existing fields
- All other models unchanged

### Core Auth Code: Not Used in SaaS Mode

The existing Campfire authentication code is **completely bypassed** in SaaS mode:

| Core Component | Status in SaaS | Reason |
|----------------|----------------|--------|
| `app/controllers/concerns/authentication.rb` | **Extended** | Includes SaaS auth when `Campfire.saas?` |
| `app/controllers/sessions_controller.rb` | **Replaced** | SaaS uses `Saas::SessionsController` |
| `app/controllers/auth_tokens_controller.rb` | **Not used** | Replaced by `Saas::AuthCodesController` |
| `app/controllers/first_runs_controller.rb` | **Skipped** | No global first run in SaaS |
| `app/models/session.rb` | **Not used** | Replaced by GlobalSession |
| `app/models/auth_token.rb` | **Not used** | Replaced by AuthCode |

**Why complete override?**
- Core auth checks `Current.account.auth_method_value` but SaaS login happens before workspace selection (no Account)
- Core uses `session[:user_id]` but SaaS has GlobalIdentity without User initially
- Core SessionsController requires User to exist, SaaS allows GlobalIdentity-only state

---

## Overview

### Critical Architecture Distinction

**Fizzy's architecture:**
- **Core app IS multi-tenant** - middleware, CurrentAttributes, Account model all in main app
- **`/saas` folder adds SaaS-specific features** - billing, admin dashboard, telemetry, security auditing
- Core tenancy code lives in `config/initializers/tenanting/` and models

**Campfire-CE's architecture (intentionally different):**
- **Core app is single-tenant** - no multi-tenancy code, works for self-hosters out of the box
- **`saas/` folder adds ALL multi-tenancy** - middleware, shared models, auth, workspace selector
- **Later:** billing/admin in same saas/ folder (v2)

**Why different?** Campfire is primarily for self-hosted single-tenant deployments. Multi-tenancy is opt-in for SaaS providers.

### Comparison Table

| Aspect | Fizzy (pre-Plan B) | Campfire-CE (Planned) |
|--------|-------|----------------------|
| Core app | **Multi-tenant** | **Single-tenant** |
| SaaS folder | Billing/admin/telemetry | **Core tenancy + billing** |
| Tenant identification | **Path-based** (7-digit ID in URL) | **Path-based** (7-digit ID in URL) |
| Database strategy | SQLite per-tenant (pre-Plan B) | Database-per-tenant (SQLite per workspace) |
| Multi-tenant mode | Toggle via ENV["SAAS"] | Toggle via ENV["SAAS"] or tmp/saas.txt |
| Identity system | Queenbee (37signals internal) | Custom GlobalIdentity |
| Billing | Stripe via SaaS DB | Stripe (v2 scope) |

**Note:** Fizzy switched to MySQL in "Plan B" for availability at 37signals scale. Pre-Plan B, they used SQLite per-tenant like us.

---

## 1. SaaS Folder Structure

### Fizzy Approach

```
saas/
├── app/
│   ├── controllers/
│   │   ├── account/subscriptions_controller.rb
│   │   ├── admin/accounts_controller.rb
│   │   └── concerns/
│   │       ├── card/limited_creation.rb      # Limit enforcement
│   │       └── admin/account_scoped.rb
│   ├── models/
│   │   ├── account/billing.rb               # Included into core Account
│   │   ├── account/subscription.rb          # SaaS DB
│   │   ├── account/billing_waiver.rb        # Comped accounts
│   │   ├── plan.rb                          # Plan definitions
│   │   └── saas_record.rb                   # Base for SaaS DB models
│   └── views/
│       ├── account/settings/
│       └── admin/accounts/
├── config/
│   ├── database.yml                         # Separate DB config for SaaS
│   └── routes.rb
├── db/
│   └── migrate/                             # SaaS-only migrations
├── lib/
│   └── fizzy/saas/
│       ├── engine.rb                        # Main engine file
│       ├── authorization.rb                 # Employee checks
│       ├── metrics.rb                       # Yabeda metrics
│       ├── signup.rb                        # Queenbee signup flow
│       └── transaction_pinning.rb           # Read replica consistency
└── fizzy-saas.gemspec
```

**Key insight**: Fizzy's core tenancy is NOT in saas/ - it's in:
- `config/initializers/tenanting/account_slug.rb` - middleware
- `app/models/current.rb` - CurrentAttributes with `with_account`/`without_account`
- `app/models/account.rb` - tenant root model

The saas/ folder only adds billing, admin, and telemetry on top of already-working multi-tenancy.

**Key pattern**: Fizzy uses `concerns/` to inject behavior into core controllers (e.g., `Card::LimitedCreation`).

### Campfire-CE Approach (Planned)

```
saas/
├── app/
│   ├── controllers/
│   │   └── saas/
│   │       ├── base_controller.rb
│   │       ├── sessions_controller.rb       # Global Identity login
│   │       ├── registrations_controller.rb
│   │       └── workspaces_controller.rb
│   ├── controllers/concerns/
│   │   └── shared_authentication.rb
│   ├── channels/concerns/
│   │   └── workspace_broadcasting.rb
│   ├── models/
│   │   ├── untenanted_record.rb
│   │   ├── global_identity.rb
│   │   ├── global_session.rb
│   │   ├── workspace.rb
│   │   └── workspace_membership.rb
│   ├── helpers/
│   │   └── workspace_selector_helper.rb
│   └── views/
├── config/
│   └── routes.rb
├── db/
│   └── untenanted_migrate/
├── lib/
│   └── campfire/
│       └── saas/
│           ├── engine.rb
│           └── tenant_resolver.rb           # Path-based workspace resolution
└── campfire-saas.gemspec
```

**Key difference**: We use `tenant_resolver.rb` with a simple lambda for path-based workspace resolution. Fizzy uses the same pattern (simple lambda in initializer).

---

## 2. Engine Loading

### Fizzy Approach

```ruby
# Gemfile.saas
eval_gemfile "Gemfile"
gem "fizzy-saas", path: "saas"

# lib/fizzy.rb
def self.saas?
  return @saas if defined?(@saas)
  @saas = !!(((ENV["SAAS"] || File.exist?(File.expand_path("../tmp/saas.txt", __dir__))) && ENV["SAAS"] != "false"))
end

def self.configure_bundle
  if saas?
    ENV["BUNDLE_GEMFILE"] = "Gemfile.saas"
  end
end
```

**How it works:**
1. Check `ENV["SAAS"]` or `tmp/saas.txt`
2. If SaaS mode, set `BUNDLE_GEMFILE=Gemfile.saas`
3. Bundler loads the engine as a gem

### Campfire-CE Approach (Same Pattern)

```ruby
# Gemfile.saas
eval_gemfile "Gemfile"
gem "campfire-saas", path: "saas"
gem "activerecord-tenanted"  # Multi-tenant gem

# lib/campfire.rb
module Campfire
  def self.saas?
    return @saas if defined?(@saas)
    @saas = ENV["SAAS"] == "true" || File.exist?(Rails.root.join("tmp/saas.txt"))
  end
end
```

**Decision**: Adopt Fizzy's pattern exactly. Simple and proven.

---

## 3. Workspace Identification (Path-Based)

### Fizzy Approach: Path-Based (Same as Campfire!)

```ruby
# config/initializers/tenanting/account_slug.rb
module AccountSlug
  PATTERN = /(\d{7,})/
  FORMAT = "%07d"
  PATH_INFO_MATCH = /\A(\/#{AccountSlug::PATTERN})/

  class Extractor
    def initialize(app)
      @app = app
    end

    # We're using account id prefixes in the URL path. Rather than namespace
    # all our routes, we're "mounting" the Rails app at this URL prefix.
    def call(env)
      request = ActionDispatch::Request.new(env)

      if request.path_info =~ PATH_INFO_MATCH
        # Yanks the prefix off PATH_INFO and move it to SCRIPT_NAME
        request.engine_script_name = request.script_name = $1
        request.path_info = $'.empty? ? "/" : $'

        # Stash the account's external ID
        env["fizzy.external_account_id"] = AccountSlug.decode($2)
      end

      if env["fizzy.external_account_id"]
        account = Account.find_by(external_account_id: env["fizzy.external_account_id"])
        Current.with_account(account) { @app.call(env) }
      else
        Current.without_account { @app.call(env) }
      end
    end
  end

  def self.decode(slug) slug.to_i end
  def self.encode(id) FORMAT % id end
end

Rails.application.config.middleware.insert_after Rack::TempfileReaper, AccountSlug::Extractor
```

**URL structure**: Workspace ID in path, exactly like our plan!
```
fizzy.com/1234567/boards/123    # Account 1234567
fizzy.com/9876543/boards/456    # Account 9876543
```

**How Fizzy generates external_account_id (sequential with lock):**
```ruby
class Account::ExternalIdSequence < ApplicationRecord
  def self.next
    with_lock do |sequence|
      sequence.increment!(:value).value
    end
  end

  def self.initial_value
    Account.maximum(:external_account_id) || 0
  end
end

# Account model
before_create :assign_external_account_id

def assign_external_account_id
  self.external_account_id ||= ExternalIdSequence.next
end

# For seeds/fixtures - deterministic from name
tenant_id = ActiveRecord::FixtureSet.identify("37signals")
# => 897362094 (large integer, 7+ digits naturally)
```

### Campfire-CE Approach: Path-Based with Tenant Resolver

Uses `activerecord-tenanted` gem's built-in tenant resolver (simpler than custom middleware):

```ruby
# saas/config/initializers/tenant_resolver.rb
WORKSPACE_PATTERN = /\A\/(\d{7,})(?:\/|$)/

Rails.application.config.active_record_tenanted.tenant_resolver = ->(request) do
  if request.path =~ WORKSPACE_PATTERN
    $1  # Returns workspace external_id as tenant string
  end
end

# The gem automatically handles:
# - Moving workspace prefix from PATH_INFO to SCRIPT_NAME
# - Setting ApplicationRecord.current_tenant
# - Wrapping request in with_tenant block
# - Switching to the correct tenant database

# Current.account is loaded from the tenant database (each workspace has its own Account)
# No separate Workspace model needed - tenant string + per-tenant Account is sufficient
```

**URL structure**: Workspace ID in path.
```
campfire.example.com/1000001/general    # Tenant 1000001
campfire.example.com/1000002/rooms      # Tenant 1000002
```

### Comparison

Both Fizzy and Campfire-CE use the **same path-based approach**:

| Aspect | Value |
|--------|-------|
| Pattern | 7+ digit numeric ID |
| Regex | `/\A(\/\d{7,})/` |
| Middleware | Extracts ID, moves to `SCRIPT_NAME` |
| Context | `Current.with_account/workspace` block |

**Key difference is what happens AFTER workspace is identified:**

| Aspect | Fizzy (pre-Plan B) | Campfire-CE |
|--------|-------|-------------|
| Database lookup | `Account.find_by(external_account_id:)` | Gem switches to tenant SQLite file automatically |
| Data access | Queries routed to tenant DB by gem | Queries routed to tenant DB by gem |
| Account access | `Account` in tenant DB | `Account` in tenant DB (same!) |
| Isolation | File-level (SQLite per tenant) | File-level (SQLite per tenant) |

**Note:** Pre-Plan B Fizzy and Campfire-CE use the same database-per-tenant approach with SQLite.

---

## 4. Database Strategy

### Fizzy Approach (Pre-Plan B): SQLite Per-Tenant

Fizzy used `activerecord-tenanted` with SQLite per-tenant before switching to MySQL in Plan B:

```ruby
# config/database.yml (pre-Plan B)
primary:
  database: storage/tenants/<%= Rails.env %>/%{tenant}/db/main.sqlite3
  tenanted: true
untenanted:
  database: storage/untenanted/<%= Rails.env %>.sqlite3

# ApplicationRecord routes to tenant DB
class ApplicationRecord < ActiveRecord::Base
  tenanted
end

# Account lives in each tenant DB
class Account < ApplicationRecord
  # No belongs_to needed - one Account per tenant DB
end
```

**Structure (pre-Plan B):**
```
storage/
├── untenanted/development.sqlite3    # Identity, Session, Membership
└── tenants/development/
    ├── 1000001/db/main.sqlite3       # Account, Users, Boards for tenant 1
    └── 1000002/db/main.sqlite3       # Account, Users, Boards for tenant 2
```

**Note:** Plan B moved to MySQL for availability at 37signals scale. We don't have those concerns.

### Campfire-CE Approach: Database-per-Tenant

```ruby
# config/database.yml (when saas enabled)
primary:
  database: "storage/workspaces/%{tenant}/main.sqlite3"
  tenanted: true
untenanted:
  database: storage/untenanted.sqlite3

# Using activerecord-tenanted gem
class ApplicationRecord < ActiveRecord::Base
  tenanted  # Routes to workspace-specific DB
end

class UntenantedRecord < ActiveRecord::Base
  connects_to database: { writing: :untenanted }
end
```

**Structure:**
```
storage/
├── untenanted.sqlite3                # Workspace registry, Identity, sessions
└── workspaces/
    ├── 1000001/main.sqlite3          # Workspace 1000001's data + Account
    ├── 1000002/main.sqlite3          # Workspace 1000002's data + Account
    └── 1000003/main.sqlite3          # Workspace 1000003's data + Account
```

### Comparison: Pre-Plan B Fizzy vs Campfire-CE

Both use database-per-tenant with SQLite. The approaches are nearly identical:

| Aspect | Fizzy (pre-Plan B) | Campfire-CE |
|--------|------------------|-------------------------|
| Database | SQLite per-tenant | SQLite per-tenant |
| Data isolation | Complete file isolation | Complete file isolation |
| Backup/restore | Copy SQLite file | Copy SQLite file |
| Gem | `activerecord-tenanted` | `activerecord-tenanted` |
| Tenant ID format | 7+ digit path | 7+ digit path |

**Why database-per-tenant works well:**
1. SQLite works best with separate files
2. Workspace backup = copy one file
3. Complete data isolation (no risk of cross-tenant leaks)
4. Delete workspace = delete folder
5. Simple deployment (no separate DB server)

---

## 5. Model Composition

### Fizzy Approach: Include Modules

```ruby
# saas/lib/fizzy/saas/engine.rb
config.to_prepare do
  ::Account.include Account::Billing, Account::Limited
  ::Signup.prepend Fizzy::Saas::Signup
  CardsController.include(Card::LimitedCreation)
  ::ApplicationController.include Fizzy::Saas::Authorization::Controller
end

# saas/app/models/account/billing.rb
module Account::Billing
  extend ActiveSupport::Concern

  def subscription
    @subscription ||= Account::Subscription.find_or_initialize_by(account: self)
  end

  def plan
    subscription.plan
  end
end
```

**Key pattern**: Engine extends core models via `include` in `to_prepare` block.

### Campfire-CE Approach: Same Pattern

```ruby
# saas/lib/campfire/saas/engine.rb
config.to_prepare do
  ::ApplicationRecord.include Campfire::Saas::Tenanted
  ::User.include Campfire::Saas::IdentityLink
  ::ApplicationController.include Campfire::Saas::SharedAuthentication
  ::ApplicationCable::Channel.include Campfire::Saas::WorkspaceBroadcasting
end
```

**Decision**: Adopt Fizzy's pattern. Clean separation while allowing extension.

---

## 6. Route Handling

### Fizzy Approach

Fizzy uses **both prepend and append** for routes:

```ruby
# saas/lib/fizzy/saas/engine.rb

class Engine < ::Rails::Engine
  # Engine mounted at root - admin routes live here
  initializer "fizzy.saas.mount" do |app|
    app.routes.append do
      mount Fizzy::Saas::Engine => "/", as: "saas"
    end
  end

  # Routes PREPENDED to main app (take precedence)
  # Used for billing routes that need to come before default routes
  initializer "fizzy.saas.prepend_routes" do |app|
    app.routes.prepend do
      namespace :account do
        resource :subscription
        resource :billing_portal, only: :show
      end
    end
  end

  # Routes APPENDED to main app (after defaults)
  # Used for admin namespace
  initializer "fizzy.saas.append_routes" do |app|
    app.routes.append do
      namespace :admin do
        # Queenbee integration
      end
    end
  end

  # Initializers for additional SaaS features
  initializer "fizzy.saas.transaction_pinning" do |app|
    # MySQL GTID-based replica consistency
    app.middleware.insert_after ActionDispatch::Executor,
      Fizzy::Saas::TransactionPinning::Middleware
  end
end

# saas/config/routes.rb
Fizzy::Saas::Engine.routes.draw do
  namespace :admin do
    resources :accounts
  end
end
```

**Route loading order:**
1. **Prepended routes** (billing) - take precedence
2. **Main app routes** - standard Campfire routes
3. **Appended routes** (admin) - after main routes
4. **Engine routes** (mounted at `/`) - engine-namespaced

**Access patterns:**
- Main app routes: `root_path`, `boards_path`
- Engine routes: `saas.admin_accounts_path`
- Prepended routes: `account_subscription_path`

### Campfire-CE Approach

```ruby
# saas/lib/campfire/saas/engine.rb

# Public routes (no workspace context)
initializer "campfire.saas.routes" do |app|
  app.routes.prepend do
    # These work without workspace prefix
    resource :registration, only: [:new, :create], controller: "saas/registrations"
    resource :session, only: [:new, :create, :destroy], controller: "saas/sessions"
    get "workspaces", to: "saas/workspaces#index"
    post "workspaces", to: "saas/workspaces#create"
  end
end

# saas/config/routes.rb
Campfire::Saas::Engine.routes.draw do
  namespace :admin do
    resources :workspaces
    resource :dashboard, only: :show
  end
end
```

**URL patterns:**
- Public: `/registration`, `/session`, `/workspaces`
- Workspace-scoped: `/1000001/rooms`, `/1000001/general`
- Admin: `/admin/workspaces`

---

## 7. Authentication Differences

### Fizzy: Queenbee Integration

```ruby
# Fizzy uses 37signals' internal Queenbee system
class Signup
  def create_tenant
    @queenbee_account = Queenbee::Remote::Account.create!(queenbee_account_attributes)
    @queenbee_account.id.to_s
  end
end
```

Queenbee handles:
- Identity creation/management
- Account creation
- Cross-product authentication (HEY, Basecamp, etc.)

### Campfire-CE: Custom GlobalIdentity (OTP-Only for MVP)

```ruby
# saas/app/models/global_identity.rb
class GlobalIdentity < UntenantedRecord
  # No password for MVP - OTP only via AuthCode
  has_many :auth_codes, dependent: :destroy
  has_many :global_sessions, dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy

  normalizes :email_address, with: ->(value) { value.strip.downcase.presence }

  def send_auth_code
    auth_codes.create!.tap do |auth_code|
      AuthCodeMailer.sign_in_instructions(auth_code).deliver_later
    end
  end

  # Get workspaces by iterating tenant DBs (no cross-DB association)
  def workspace_names
    workspace_memberships.filter_map(&:account_name)
  end
end

# saas/app/models/global_session.rb
class GlobalSession < UntenantedRecord
  belongs_to :global_identity
  has_secure_token :token
end
```

**Flow:**
1. User enters email → GlobalIdentity found or created in untenanted DB
2. AuthCode sent via email with 6-digit code
3. User enters code → GlobalSession created → cookie set
4. User selects/creates workspace → WorkspaceMembership created
5. User visits workspace → Tenant DB activated → User record found/created

---

## 8. Billing & Limits

### Fizzy Approach

```ruby
# saas/app/models/plan.rb
PLANS = {
  free_v1: {
    name: "Free",
    price: 0,
    card_limit: 1000,
    storage_limit: 1.gigabytes
  },
  monthly_v1: {
    name: "Unlimited",
    price: 20,
    card_limit: Float::INFINITY,
    storage_limit: 5.gigabytes
  },
}

# saas/app/models/account/limited.rb
module Account::Limited
  def exceeding_limits?
    exceeding_card_limit? || exceeding_storage_limit?
  end

  def card_limit
    overridden_limits&.card_limit || plan.card_limit
  end
end

# Enforcement via controller concern
# saas/app/controllers/concerns/card/limited_creation.rb
module Card::LimitedCreation
  extend ActiveSupport::Concern
  included do
    before_action :ensure_under_limits, only: [:create]
  end
end
```

**Features:**
- Plans defined in code
- Limits can be overridden per-account (admin feature)
- Billing waivers for comped accounts
- Stripe webhooks for subscription state

### Campfire-CE Approach (v2)

```ruby
# v2 scope - similar pattern
# saas/app/models/plan.rb
class Plan
  PLANS = {
    free: { name: "Free", users_limit: 10, storage_limit: 1.gigabyte },
    pro: { name: "Pro", users_limit: Float::INFINITY, storage_limit: 10.gigabytes },
  }
end

# Enforcement in workspace controller
before_action :ensure_under_limits, only: [:invite_user]
```

**Decision**: Defer billing to v2. Focus on multi-tenancy infrastructure first.

---

## 9. Key Differences Summary

| Feature | Fizzy (pre-Plan B) | Campfire-CE |
|---------|-------|-------------|
| Engine structure | Same | Same |
| Gemfile.saas pattern | Same | Same |
| SaaS detection | Same | Same |
| Model composition | Same | Same |
| Tenant identification | **Path-based** | **Path-based** |
| Database | Per-tenant (SQLite files) | Per-tenant (SQLite files) |
| Identity | Queenbee (external) | Custom GlobalIdentity (OTP-only) |
| Account model | Per-tenant DB | Per-tenant DB |
| Workspace model | None (tenant string + Account) | None (tenant string + Account) |
| Billing | In engine | v2 scope |
| Middleware | Path extraction via gem | Path extraction via gem |

---

## 10. Decisions for Campfire-CE

### Adopt from Fizzy (pre-Plan B):
1. **Rails Engine pattern** - Clean separation, proven approach
2. **Gemfile.saas** - Same eval_gemfile pattern
3. **SaaS detection** - ENV["SAAS"] or tmp/saas.txt
4. **Model composition** - Include modules in to_prepare
5. **Admin namespace** - For workspace management
6. **Path-based tenant ID** - Same 7-digit pattern, same middleware approach
7. **Database-per-tenant** - Same SQLite per-tenant architecture
8. **No Workspace model** - Tenant string + per-tenant Account (same pattern)

### Different from Fizzy:
1. **Custom GlobalIdentity** - No external dependency like Queenbee (OTP-only for MVP)
2. **Core app is single-tenant** - Fizzy's core is multi-tenant, ours is single-tenant with optional SaaS layer

### Deferred to v2:
1. Billing/Stripe integration
2. Usage limits enforcement
3. Plan management
4. Password authentication for GlobalIdentity (optional)

---

## 11. Implementation Notes

### Engine Initialization Order

```ruby
# saas/lib/campfire/saas/engine.rb
module Campfire
  module Saas
    class Engine < ::Rails::Engine
      isolate_namespace Campfire::Saas

      # 1. Add middleware early
      initializer "campfire.saas.middleware", before: :build_middleware_stack do |app|
        app.middleware.insert_before 0, Campfire::Saas::WorkspaceMiddleware
      end

      # 2. Extend models after they're loaded
      config.to_prepare do
        ::ApplicationRecord.tenanted if Campfire.saas?
        ::User.include Campfire::Saas::IdentityLink
      end

      # 3. Add routes
      initializer "campfire.saas.routes" do |app|
        app.routes.prepend do
          # Public routes...
        end
      end

      # 4. Mount engine
      initializer "campfire.saas.mount" do |app|
        app.routes.append do
          mount Campfire::Saas::Engine => "/saas"
        end
      end
    end
  end
end
```

### Database Configuration

```yaml
# saas/config/database.yml.saas
# This replaces config/database.yml when in SaaS mode

default: &default
  adapter: sqlite3

development:
  primary:
    <<: *default
    database: storage/workspaces/development/%{tenant}/main.sqlite3
    tenanted: true
  untenanted:
    <<: *default
    database: storage/development/untenanted.sqlite3
    migrations_paths:
      - <%= Rails.root.join("saas/db/untenanted_migrate") %>
```

### Testing Setup

```ruby
# saas/test/test_helper.rb
require_relative "../../../test/test_helper"

class ActiveSupport::TestCase
  # Set up tenant for tests
  # The gem uses a default tenant from config or ARTENANT env var
  setup do
    # Tenant is set automatically by activerecord-tenanted gem
    # Default: "test-tenant" in test environment
    # Override with: ARTENANT=1000001 bin/rails test
  end
end
```

---

## 12. 37signals Style Guide Insights (Relevant to Campfire)

From `/Users/ashwin/dev/unofficial-37signals-coding-style-guide`

### Multi-Tenancy Patterns

#### Defense in Depth: Always Scope Controller Lookups

Don't rely solely on middleware for tenant isolation:

```ruby
# Bad - assumes middleware context
def set_message
  @message = Message.find(params[:id])
end

# Good - scope through tenant
def set_message
  @message = Current.account.messages.find(params[:id])
end

# Better - scope through user's accessible records
def set_room
  @room = Current.user.accessible_rooms.find(params[:id])
end
```

#### Session Cookie Path Scoping

Critical for multi-tenant apps where user may be logged into multiple workspaces:

```ruby
def set_current_session(session)
  cookies.signed.permanent[:session_token] = {
    value: session.signed_id,
    httponly: true,
    same_site: :lax,
    path: request.script_name  # e.g., "/1000001" - set by tenant middleware
  }
end
```

**Why**: Without path scoping, cookies from one workspace clobber another.

#### ActiveJob Tenant Preservation

Automatically capture/restore tenant in background jobs:

```ruby
module TenantedActiveJobExtensions
  def initialize(...)
    super
    @workspace_id = ApplicationRecord.current_tenant
  end

  def serialize
    super.merge("workspace_id" => @workspace_id)
  end

  def deserialize(job_data)
    super
    @workspace_id = job_data["workspace_id"]
  end

  def perform_now
    if @workspace_id.present?
      ApplicationRecord.with_tenant(@workspace_id) { super }
    else
      super
    end
  end
end

ActiveSupport.on_load(:active_job) do
  prepend TenantedActiveJobExtensions
end
```

#### Recurring Jobs Must Iterate All Tenants

```ruby
class DailyDigestJob < ApplicationJob
  def perform
    ApplicationRecord.with_each_tenant do |tenant_id|
      User.wants_daily_digest.find_each do |user|
        DigestMailer.daily(user).deliver_later
      end
    end
  end
end
```

**Note**: "Easy to forget during multi-tenant migration" - scheduled jobs run outside request context.

#### Default Tenant for Dev Console

Makes `rails console` ergonomic without constant tenant switching:

```ruby
# config/initializers/tenanting/default_tenant.rb
Rails.application.configure do
  if Rails.env.development?
    config.active_record_tenanted.default_tenant = "1000001"
  end
end
```

#### Test Setup for Path-Based Tenancy

```ruby
# test_helper.rb
Rails.application.config.active_record_tenanted.default_tenant =
  ActiveRecord::FixtureSet.identify(:default_workspace)

class ActionDispatch::IntegrationTest
  setup do
    integration_session.default_url_options[:script_name] =
      "/#{ApplicationRecord.current_tenant}"
  end
end

class ActionDispatch::SystemTestCase
  setup do
    self.default_url_options[:script_name] =
      "/#{ApplicationRecord.current_tenant}"
  end
end
```

#### Test Middleware in Isolation

```ruby
def call_with_env(path, extra_env = {})
  captured = {}
  extra_env = { "action_dispatch.routes" => Rails.application.routes }.merge(extra_env)

  app = ->(env) do
    captured[:script_name] = env["SCRIPT_NAME"]
    captured[:path_info] = env["PATH_INFO"]
    captured[:current_tenant] = ApplicationRecord.current_tenant
    [ 200, {}, [ "ok" ] ]
  end

  middleware = TenantMiddleware.new(app)
  middleware.call Rack::MockRequest.env_for(path, extra_env.merge(method: "GET"))

  captured
end

test "moves tenant prefix from PATH_INFO to SCRIPT_NAME" do
  tenant_id = "1000001"

  captured = call_with_env "/#{tenant_id}/rooms"

  assert_equal "/#{tenant_id}", captured.fetch(:script_name)
  assert_equal "/rooms", captured.fetch(:path_info)
  assert_equal tenant_id, captured.fetch(:current_tenant)
end
```

### Authentication Comparison: Campfire vs 37signals

#### Architecture Overview

| Aspect | Campfire (Current) | 37signals/Fizzy |
|--------|-------------------|-----------------|
| Model structure | User has_secure_password + AuthToken for OTP | Identity + AuthCode (no passwords) |
| Session storage | Session model with token | Session model with signed_id |
| Auth methods | Password OR OTP (configurable) | Passwordless only (magic links) |
| Multi-account | Not supported | Identity → many Users (accounts) |
| Bot support | Yes (bot_key param) | Via AccessToken/Bearer |
| Rate limiting | Not built-in | Rails 7.1+ rate_limit |

#### Campfire's Current Approach

```ruby
# User model - dual auth
class User < ApplicationRecord
  has_secure_password  # Password auth
  has_many :auth_tokens # OTP auth
end

# AuthToken - 6-digit OTP code
class AuthToken < ApplicationRecord
  belongs_to :user
  has_secure_token :token
  # 6-digit code with expiration
  # Looked up by email + code
end

# Session - browser session tracking
class Session < ApplicationRecord
  belongs_to :user
  has_secure_token
  # Tracks user_agent, ip_address, last_active_at
end

# Authentication concern
module Authentication
  def require_authentication
    restore_authentication || bot_authentication || request_authentication
  end

  # Cookie: session_token -> Session -> User
end
```

**Campfire's strengths:**
- Supports both password AND OTP (configurable per-account)
- Bot authentication via bot_key
- Clean session tracking with IP/user-agent

**Campfire's gaps for multi-tenant:**
- User model tied to single account (no Identity separation)
- No cross-workspace session support
- Cookie not scoped to workspace path

#### 37signals Approach

```ruby
# Identity - global user identity (no password)
class Identity < ApplicationRecord
  has_many :auth_codes  # Passwordless auth
  has_many :sessions
  has_many :users        # One identity, many accounts
  has_many :accounts, through: :users
end

# AuthCode - 6-digit code (destroyed after use, returns identity)
class AuthCode < UntenantedRecord
  belongs_to :identity
  enum :purpose, %w[sign_in sign_up]

  def self.consume(code)
    active.find_by(code: Code.sanitize(code))&.consume
  end

  def consume
    identity.tap { destroy }  # Returns identity, then destroys self
  end
end

# Session - belongs to Identity, not User
class Session < ApplicationRecord
  belongs_to :identity
end

# Authentication concern
module Authentication
  def require_authentication
    resume_session || authenticate_by_bearer_token || request_authentication
  end

  # Uses signed_id instead of raw token
  def set_current_session(session)
    cookies.signed.permanent[:session_token] = {
      value: session.signed_id,  # Not raw token!
      path: "/#{account.external_id}"  # Scoped to tenant path
    }
  end
end
```

**37signals strengths:**
- Identity separate from User (cross-account support)
- AuthCode consumed (destroyed) on use - cleaner
- Session cookie scoped to tenant path
- Uses `signed_id` (more secure than raw tokens)
- Rate limiting built-in (Rails 7.1+)
- Controller DSL: `require_untenanted_access`, `require_unauthenticated_access`

#### Key Differences

| Feature | Campfire | 37signals |
|---------|----------|-----------|
| Token in cookie | Raw `session.token` | `session.signed_id` |
| OTP model | `AuthToken` (kept, marked used) | `AuthCode` (destroyed on use) |
| OTP lookup | By email + code | By code only (scoped to identity) |
| Cookie path | Global (COOKIE_DOMAIN) | Scoped to tenant (`/1000001`) |
| Session belongs to | User | Identity |
| Multi-account | No | Yes (Identity → many Users) |

#### What Campfire Should Adopt for Multi-Tenancy

1. **Separate GlobalIdentity from User**
   - GlobalIdentity = global (email, OTP-only for MVP)
   - User = per-workspace (role, permissions)

2. **GlobalSession belongs to GlobalIdentity, not User**
   - Allows cross-workspace session

3. **Cookie path scoping**
   ```ruby
   cookies.signed.permanent[:session_token] = {
     value: global_session.signed_id,
     path: request.script_name  # "/1000001" - set by middleware
   }
   ```

4. **Controller DSL for tenant-awareness**
   ```ruby
   class SessionsController < ApplicationController
     require_untenanted_access  # Login page has no workspace context
     require_unauthenticated_access except: :destroy
   end
   ```

5. **Rate limiting** (Rails 7.1+)
   ```ruby
   rate_limit to: 10, within: 3.minutes, only: :create
   ```

#### Migration Path

Campfire keeps single-tenant mode unchanged. Multi-tenant adds GlobalIdentity (OTP-only for MVP):

```ruby
# Multi-tenant structure (OTP-only for MVP)
class GlobalIdentity < UntenantedRecord
  # No password for MVP - OTP only via AuthCode
  has_many :auth_codes, dependent: :destroy
  has_many :global_sessions, dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy
  # Note: No has_many :workspaces - can't have cross-DB associations
end

class User < ApplicationRecord
  belongs_to :workspace_membership, optional: true  # nil in single-tenant mode
  has_one :global_identity, through: :workspace_membership, disable_joins: true

  # Existing password fields stay for single-tenant mode
  # In multi-tenant mode, auth is via GlobalIdentity → AuthCode
  has_secure_password validations: false
end
```

**Note:** Password support for GlobalIdentity can be added in v2 if needed.

### Authentication Patterns (continued)

#### Passwordless Magic Links (~150 lines custom code)

37signals prefers custom passwordless auth over Devise:

```ruby
class AuthCode < ApplicationRecord
  CODE_LENGTH = 6
  EXPIRATION_TIME = 15.minutes

  belongs_to :identity
  scope :active, -> { where(expires_at: Time.current...) }

  before_validation :generate_code, :set_expiration, on: :create

  def self.consume(code)
    active.find_by(code: Code.sanitize(code))&.consume
  end

  def consume
    destroy
    self
  end

  private
    def generate_code
      self.code = SecureRandom.random_number(10**CODE_LENGTH).to_s.rjust(CODE_LENGTH, "0")
    end

    def set_expiration
      self.expires_at = EXPIRATION_TIME.from_now
    end
end
```

#### Controller DSL for Authentication

```ruby
module Authentication
  extend ActiveSupport::Concern

  class_methods do
    # For login/signup pages - redirect if already logged in
    def require_unauthenticated_access(**options)
      allow_unauthenticated_access **options
      before_action :redirect_authenticated_user, **options
    end

    # For public pages that optionally show user info
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      before_action :resume_session, **options
    end

    # For non-tenanted pages (login, workspace selector)
    def require_untenanted_access(**options)
      skip_before_action :require_workspace, **options
      before_action :redirect_tenanted_request, **options
    end
  end
end
```

#### Rate Limiting (Rails 7.1+)

```ruby
class SessionsController < ApplicationController
  require_untenanted_access
  require_unauthenticated_access except: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Try again later." }
end
```

### ActionCable Multi-Tenancy

#### WebSocket Connection Must Establish Tenant Context

The `activerecord-tenanted` gem handles ActionCable connections automatically via its `CableConnection` module:

```ruby
# The gem prepends this to ApplicationCable::Connection
# It extracts tenant from the WebSocket URL path and sets context

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      # Gem has already set ApplicationRecord.current_tenant from URL path
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        if global_session = find_global_session_by_cookie
          # Tenant context already set by gem - we're in the tenant DB
          if workspace_membership = global_session.global_identity.workspace_memberships.find_by(tenant: ApplicationRecord.current_tenant)
            self.current_user = workspace_membership.user
          end
        end
      end

      def find_global_session_by_cookie
        GlobalSession.find_by(token: cookies.signed[:session_token])
      end
  end
end
```

#### Tenant-Scoped Broadcasts

```ruby
# app/helpers/tenanting_helper.rb
def tenanted_action_cable_meta_tag
  tag "meta",
      name: "action-cable-url",
      content: "#{request.script_name}#{ActionCable.server.config.mount_path}"
end
```

### Database Patterns

#### Hard Deletes, Not Soft Deletes

```ruby
# Bad
class Message < ApplicationRecord
  scope :active, -> { where(deleted_at: nil) }
end

# Good - just delete it
message.destroy
```

**Why**: Simpler queries. If you need history, use audit logs.

**Note**: Campfire currently uses soft deletes for messages (`active` boolean). Consider if this is truly needed.

#### State as Records, Not Booleans

```ruby
# Bad - boolean flag loses context
class Room < ApplicationRecord
  # closed: boolean
  def close
    update!(closed: true)
  end
end

# Good - state record with attribution
class Room < ApplicationRecord
  has_one :closure, dependent: :destroy

  def closed?
    closure.present?
  end

  def close(by:)
    create_closure!(creator: by)
  end
end

class Closure < ApplicationRecord
  belongs_to :room
  belongs_to :creator, class_name: "User"
  # Timestamps = WHEN, creator = WHO
end
```

### Routing Patterns

#### CRUD Over Custom Actions

```ruby
# BAD: Custom actions
resources :rooms do
  post :close
  post :archive
  post :pin
end

# GOOD: New resources for each state change
resources :rooms do
  resource :closure      # POST to close, DELETE to reopen
  resource :archive      # POST to archive
  resource :pin          # POST to pin, DELETE to unpin
end
```

### Model Patterns

#### Rich Domain Models with Composable Concerns

```ruby
class Message < ApplicationRecord
  include Broadcastable, Mentionable, Searchable,
          Attachments, RichText, Boostable, Bookmarkable

  belongs_to :room
  belongs_to :creator, class_name: "User", default: -> { Current.user }
end
```

Each concern is 50-150 lines, self-contained with associations, scopes, and methods.

#### Default Values via Lambdas

```ruby
class Message < ApplicationRecord
  belongs_to :room
  belongs_to :creator, class_name: "User", default: -> { Current.user }
  # Account derived from room
  belongs_to :account, default: -> { room.account }
end
```

### Key Principles

1. **Vanilla Rails over abstractions** - Thin controllers, rich models, no service objects unless truly justified
2. **Let it crash** - Use bang methods (`create!`), rescue meaningfully
3. **Database constraints over AR validations** - Let DB enforce integrity
4. **Write-time computation, not read-time** - Enables pagination, caching
5. **Question every layer of indirection** - "Is this abstraction earning its keep?"

---

## 13. Additional Patterns to Adopt from Fizzy

### Join Code System for Workspace Invites

Fizzy implements a robust join code system for inviting users to workspaces:

```ruby
# app/models/account/join_code.rb
class Account::JoinCode < ApplicationRecord
  CODE_LENGTH = 12
  USAGE_LIMIT_MAX = 10_000_000_000

  belongs_to :account

  validates :usage_limit, numericality: {
    less_than_or_equal_to: USAGE_LIMIT_MAX,
    message: "cannot be larger than the population of the planet"
  }

  scope :active, -> { where("usage_count < usage_limit") }

  before_create :generate_code, if: -> { code.blank? }

  def redeem_if(&block)
    with_lock do
      increment!(:usage_count) if active? && block.call(account)
    end
  end

  def active?
    usage_count < usage_limit
  end

  def reset
    generate_code
    self.usage_count = 0
    save!
  end

  private
    def generate_code
      self.code = loop do
        candidate = SecureRandom.base58(CODE_LENGTH).scan(/.{4}/).join("-")
        break candidate unless self.class.exists?(code: candidate)
      end
    end
end
```

**Key features:**
- 12-character code formatted as `XXXX-XXXX-XXXX`
- Usage limits with atomic locking (`with_lock`)
- Redeemable via `redeem_if` block pattern
- Can be reset (regenerates code, resets count)

**Controller pattern:**
```ruby
class JoinCodesController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create

  def create
    @join_code.redeem_if { |account| @identity.join(account) }
    user = User.active.find_by!(account: @join_code.account, identity: @identity)

    if @identity == Current.identity && user.setup?
      redirect_to landing_url(script_name: @join_code.account.slug)
    else
      redirect_to_session_auth_code @identity.send_auth_code
    end
  end
end
```

**Campfire already has this:** The `Account::Joinable` concern stores `join_code` directly on Account (per-tenant). Each workspace's Account has its own join code. The existing implementation is simpler than Fizzy's (no usage limits/tracking) but works correctly for multi-tenant.

---

### Background Jobs Patterns

#### Transaction Safety
```ruby
# Prevent jobs from running before data exists
ActiveJob::Base.enqueue_after_transaction_commit = true
```

#### SMTP Error Handling
```ruby
module SmtpDeliveryErrorHandling
  extend ActiveSupport::Concern

  included do
    # Retry transient errors
    retry_on Net::OpenTimeout, Net::ReadTimeout, Socket::ResolutionError,
      wait: :polynomially_longer

    # Swallow permanent errors gracefully
    rescue_from Net::SMTPFatalError do |error|
      case error.message
      when /\A550 5\.1\.1/  # Unknown user
        Rails.logger.info "Email delivery failed: #{error.message}"
      else
        raise
      end
    end
  end
end

# Apply to ActionMailer
Rails.application.config.to_prepare do
  ActionMailer::MailDeliveryJob.include SmtpDeliveryErrorHandling
end
```

#### `_later` and `_now` Convention
```ruby
class Message < ApplicationRecord
  after_create_commit :notify_recipients_later

  def notify_recipients
    # Actual work
    Notifier.for(self)&.notify
  end

  private
    def notify_recipients_later
      NotifyRecipientsJob.perform_later(self)
    end
end

class NotifyRecipientsJob < ApplicationJob
  def perform(message)
    message.notify_recipients
  end
end
```

#### Stagger Recurring Jobs
```yaml
# Bad - all at :00
job_a: every hour at minute 0
job_b: every hour at minute 0

# Good - staggered
job_a: every hour at minute 12
job_b: every hour at minute 50
```

---

### Webhook System with SSRF Protection

#### SSRF Protection Module
```ruby
module SsrfProtection
  extend self

  DISALLOWED_IP_RANGES = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("198.18.0.0/15")
  ].freeze

  def resolve_public_ip(hostname)
    ip_addresses = resolve_dns(hostname)
    public_ips = ip_addresses.reject { |ip| private_address?(ip) }
    public_ips.sort_by { |ipaddr| ipaddr.ipv4? ? 0 : 1 }.first&.to_s
  end

  def private_address?(ip)
    ip = IPAddr.new(ip.to_s) unless ip.is_a?(IPAddr)
    ip.private? || ip.loopback? || ip.link_local? || ip.ipv4_mapped? || in_disallowed_range?(ip)
  end
end
```

#### Delivery with State Machine
```ruby
class Webhook::Delivery < ApplicationRecord
  enum :state, %w[ pending in_progress completed errored ].index_by(&:itself), default: :pending

  store :request, coder: JSON
  store :response, coder: JSON

  after_create_commit :deliver_later

  def deliver
    in_progress!
    self.response = perform_request
    self.state = :completed
    save!
    webhook.delinquency_tracker.record_delivery_of(self)
  rescue
    errored!
    raise
  end

  def succeeded?
    completed? && response[:error].blank? && response[:code].between?(200, 299)
  end
end
```

#### Delinquency Tracking (Auto-disable after failures)
```ruby
class Webhook::DelinquencyTracker < ApplicationRecord
  DELINQUENCY_THRESHOLD = 10
  DELINQUENCY_DURATION = 1.hour

  def record_delivery_of(delivery)
    if delivery.succeeded?
      reset
    else
      increment!(:consecutive_failures_count, touch: true)
      webhook.deactivate if delinquent?
    end
  end

  def delinquent?
    consecutive_failures_count >= DELINQUENCY_THRESHOLD &&
      first_failure_at&.before?(DELINQUENCY_DURATION.ago)
  end
end
```

**Adopt for Campfire:** The existing webhook system could benefit from SSRF protection and delinquency tracking.

---

### Notification Bundling with Time Windows

```ruby
class Notification::Bundle < ApplicationRecord
  belongs_to :user
  enum :status, %i[ pending processing delivered ]

  scope :due, -> { pending.where("ends_at <= ?", Time.current) }
  scope :containing, ->(notification) {
    where("starts_at <= ? AND ends_at > ?", notification.created_at, notification.created_at)
  }

  # Query notifications in window dynamically - no foreign keys needed!
  def notifications
    user.notifications.where(created_at: starts_at..ends_at).unread
  end
end

class Notification < ApplicationRecord
  after_create :bundle

  private
    def bundle
      user.bundle(self) if user.settings.bundling_emails?
    end
end
```

**Key insight:** Time window queries instead of foreign keys - simpler schema, notifications are immutable.

---

### Current Context Pattern

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :global_session, :workspace_membership
  attribute :http_method, :request_id, :user_agent, :ip_address, :referrer

  # Derive global_identity and user via delegates (Fizzy pattern adapted for Campfire)
  delegate :global_identity, to: :global_session, allow_nil: true
  delegate :user, to: :workspace_membership, allow_nil: true

  # Setting global_session auto-looks up workspace_membership for current tenant
  def global_session=(value)
    super(value)
    unless value.nil?
      self.workspace_membership = global_identity.workspace_memberships.find_by(tenant: ApplicationRecord.current_tenant)
    end
  end

  def with_workspace(value, &)
    with(workspace: value, &)
  end

  def without_account(&)
    with(account: nil, &)
  end
end
```

**Adopt for Campfire:** Current pattern for cascading identity → user lookup within workspace context.

---

### ActionCable Multi-Tenant Patterns

#### Account-Scoped Broadcasts (Critical!)
```ruby
# WRONG - broadcasts to ALL accounts!
<%= turbo_stream_from :all_rooms %>

# CORRECT - scoped to current account
<%= turbo_stream_from [ Current.account, :all_rooms ] %>
```

**Why:** Without scoping, updates in one workspace trigger broadcasts to ALL connected clients. Self-DoS vulnerability.

#### Dual Broadcasting for Flexibility
```ruby
module Room::Broadcastable
  extend ActiveSupport::Concern

  included do
    broadcasts_refreshes
    broadcasts_refreshes_to ->(room) { [ room.account, :all_rooms ] }
  end
end
```

#### Forcibly Disconnect Users
```ruby
def deactivate
  transaction do
    update! active: false
    ActionCable.server.remote_connections.where(current_user: self).disconnect(reconnect: false)
  end
end
```

---

### Active Storage Patterns

#### Variant Preprocessing
```ruby
has_many_attached :embeds do |attachable|
  attachable.variant :small,
    resize_to_limit: [800, 600],
    preprocessed: true  # Prevents on-the-fly transformation failures
end
```

#### Direct Upload Expiry Extension
```ruby
# For CDN-proxied uploads (Cloudflare buffers can cause timeouts)
module ActiveStorage
  mattr_accessor :service_urls_for_direct_uploads_expire_in,
    default: 48.hours
end
```

#### Avatar Optimization (Redirect to Blob URL)
```ruby
def show
  if @user.avatar.attached?
    redirect_to rails_blob_url(@user.avatar.variant(:thumb))
  else
    render_initials if stale?(@user)
  end
end
```

**Why:** Streaming through Rails ties up workers. Redirect lets storage service (S3) serve directly.

---

### Caching Patterns

#### HTTP Caching with ETags
```ruby
def show
  @tags = Current.account.tags.alphabetically
  @boards = Current.user.boards.ordered_by_recently_accessed

  fresh_when etag: [@tags, @boards]
end
```

**Warning:** Don't HTTP cache pages with forms - CSRF tokens get stale.

#### Lazy-Loaded Turbo Frames for Expensive Menus
```erb
<%= turbo_frame_tag "my_menu",
      src: my_menu_path,
      loading: :lazy,
      target: "_top" do %>
  <%= render "my/menus/skeleton" %>
<% end %>
```

#### Client-Side Personalization in Cached Fragments
```erb
<% cache card do %>
  <div data-creator-id="<%= card.creator_id %>"
       data-controller="ownership"
       data-ownership-current-user-value="<%= Current.user.id %>">
    <button data-ownership-target="ownerOnly"
            class="hidden">Delete</button>
  </div>
<% end %>
```

Move user-specific logic to JavaScript to preserve cache effectiveness.

---

### Email Unsubscribe with Signed Tokens

```ruby
module User::Notifiable
  included do
    generates_token_for :unsubscribe, expires_in: 1.month
  end
end

class Notifications::UnsubscribesController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :verify_authenticity_token

  def create
    if user = User.find_by_token_for(:unsubscribe, params[:access_token])
      user.settings.bundle_email_never!
      redirect_to notifications_unsubscribe_path(access_token: params[:access_token])
    else
      redirect_to root_path, alert: "Invalid unsubscribe link"
    end
  end
end
```

**Headers for RFC compliance:**
```ruby
headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
headers["List-Unsubscribe"] = "<#{notifications_unsubscribe_url(access_token: @unsubscribe_token)}>"
```

---

### User Settings as Separate Model

```ruby
module User::Configurable
  extend ActiveSupport::Concern

  included do
    has_one :settings, class_name: "User::Settings", dependent: :destroy
    after_create :create_settings, unless: :system?
  end
end

class User::Settings < ApplicationRecord
  belongs_to :user

  enum :bundle_email_frequency, %i[ never every_few_hours daily weekly ],
    default: :every_few_hours, prefix: :bundle_email

  def bundle_aggregation_period
    case bundle_email_frequency
    when "every_few_hours" then 4.hours
    when "daily" then 1.day
    when "weekly" then 1.week
    else 1.day
    end
  end
end
```

**Benefits:** Keeps User model focused, settings-specific logic encapsulated.

---

## 14. Summary: What to Adopt from Fizzy

### High Priority (MVP)

| Pattern | Description | Campfire Benefit |
|---------|-------------|-----------------|
| Path-based workspace ID | Same 7-digit pattern, middleware approach | Already planned, confirmed approach |
| External ID Sequence | Sequential with database locking | Deterministic workspace IDs |
| Join Code System | Secure invite links with usage limits | Better than current invite system |
| Cookie path scoping | Session cookies per workspace | Multi-workspace login support |
| Current context cascade | `global_session=` → `global_identity=` → `user=` | Clean auth flow |
| Account-scoped broadcasts | Always prefix broadcasts with account | Prevent cross-tenant leaks |

### Medium Priority (v1)

| Pattern | Description | Campfire Benefit |
|---------|-------------|-----------------|
| Delinquency tracking | Auto-disable failing webhooks | Reduce webhook noise |
| SSRF protection | DNS pinning for webhooks | Security hardening |
| Email bundling | Time window notification batches | Less email spam |
| Settings model | Separate User::Settings | Cleaner User model |
| Controller DSL | `allow_unauthenticated_access`, etc. | Clearer controller intent |

### Lower Priority (v2)

| Pattern | Description | Campfire Benefit |
|---------|-------------|-----------------|
| Lazy turbo frames | Defer expensive menu loads | Performance |
| Client-side cache personalization | JS handles user-specific UI | Better cache hit rate |
| Avatar redirect | Let S3 serve avatars | Reduce worker load |
| Unsubscribe tokens | `generates_token_for :unsubscribe` | RFC-compliant emails |

---

## References

- Fizzy codebase: `/Users/ashwin/dev/fizzy`
- 37signals Style Guide: `/Users/ashwin/dev/unofficial-37signals-coding-style-guide`
- activerecord-tenanted: https://github.com/basecamp/activerecord-tenanted
- Rails Engines Guide: https://guides.rubyonrails.org/engines.html
