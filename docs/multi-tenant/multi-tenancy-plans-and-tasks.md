# Multi-Tenancy Implementation Tasks

Detailed task breakdown for implementing multi-tenancy in Sabha with GlobalIdentity.

**Related Documents:**
- [Product PRD](./multi-tenancy-product-prd.md) - Business goals, user stories, requirements
- [Technical PRD](./multi-tenancy-technical-prd.md) - Architecture and requirements
- [Architecture Notes](./multitenant-saas-notes.md) - Fizzy comparison and patterns
- [User Flows](./multi-tenant-user-flows.md) - Detailed user journeys

**Key Architecture Decisions:**
- **Core app = Single-tenant** - Works out of the box for self-hosters with existing Account model
- **SaaS layer = Multi-tenancy opt-in** - All multi-tenancy code lives in `saas/` folder
- **Workspace ID**: Path prefix with 7+ digit numeric ID (like Fizzy)
- **Database**: Per-workspace SQLite files (each with its own Account for settings)
- **GlobalIdentity + User Pattern (Adopted from Fizzy's "Identity" approach)**: See below
- **URLs**: `/{workspace_id}/rooms/general` not subdomains

**GlobalIdentity + User Pattern (Adopted from Fizzy):**

```
Untenanted DB                     Workspace DB
┌───────────────┐                ┌───────────────┐
│ GlobalIdentity│                │     User      │
│ ─────────────│                │ ─────────────│
│ email        │                │ workspace_    │←─┐
│ sessions     │                │ membership_id │  │
└───────┬───────┘                │ name, role    │  │
        │                        └───────┬───────┘  │
        │ global_identity_id             │          │
┌───────▼───────┐                        │          │
│ Workspace-    │────────────────────────┘          │
│ Membership    │  (cross-DB link via               │
│ ─────────────│   workspace_membership_id)        │
│ global_      │                                    │
│  identity_id │                                    │
│ tenant       │  ← workspace external_id           │
└───────────────┘                ┌───────▼───────┐
                                 │ Messages,     │
                                 │ Room Members, │
                                 │ etc.          │
                                 └───────────────┘
```

- **GlobalIdentity** (untenanted DB) = "Can this person authenticate?" (email + OTP, sessions)
- **User** (workspace DB) = "What can this person do here?" (name, role, permissions)
- **Why?** All existing `user_id` FKs stay in workspace DB. User links to WorkspaceMembership, gets GlobalIdentity via `has_one :through`.
- **Self-hosted mode**: WorkspaceMembership not used, `workspace_membership_id = nil`, User handles auth directly
- **Multi-tenant mode**: GlobalIdentity handles auth, WorkspaceMembership links global_identity to tenant, User handles workspace presence

See [multitenant-saas-notes.md](./multitenant-saas-notes.md) for detailed comparison with Fizzy.

**Terminology:**
- `Account` = Workspace-local settings (auth method, permissions). Stays in each workspace DB.
- `Tenant` = Internal gem term for database isolation. Not user-facing.
- `Workspace` = User-facing term for a chat community. Registry in untenanted DB (external_id, name, slug).
- `GlobalIdentity` = Global authentication (email + OTP code). No password for MVP. No name/avatar - those are on User.
- `GlobalSession` = Cross-workspace session. Belongs to GlobalIdentity. Stored in untenanted DB.
- `User` = Workspace-specific presence (name, role, avatar). Created from GlobalIdentity when joining.

---

## MVP Phase

**Goal**: Working multi-workspace SaaS layer with GlobalIdentity and workspace switching. Core app unchanged.

**All multi-tenancy code lives in `saas/` folder** - keeps core app clean for single-tenant deployments.

### MVP-0: SaaS Folder Structure

Reference: [Rails Engines Guide](https://guides.rubyonrails.org/engines.html)

**Engine Type:** Non-isolated (no namespace prefix on tables/models) - we extend Sabha, not create separate app.

- [x] Create `saas/` folder as Rails engine
  ```
  saas/
  ├── app/
  │   ├── controllers/
  │   │   └── saas/
  │   │       ├── application_controller.rb  # Inherits ::ApplicationController
  │   │       ├── sessions_controller.rb
  │   │       ├── auth_codes_controller.rb
  │   │       ├── registrations_controller.rb
  │   │       └── workspaces_controller.rb
  │   ├── controllers/concerns/
  │   │   └── saas/
  │   │       └── authentication.rb          # Replaces core Authentication
  │   ├── models/
  │   │   ├── global_identity.rb
  │   │   ├── global_session.rb
  │   │   ├── auth_code.rb
  │   │   ├── workspace.rb
  │   │   ├── workspace_membership.rb
  │   │   └── untenanted_record.rb
  │   ├── mailers/
  │   │   └── auth_code_mailer.rb
  │   └── views/
  │       └── saas/
  │           ├── sessions/
  │           ├── auth_codes/
  │           ├── registrations/
  │           └── workspaces/
  ├── config/
  │   ├── routes.rb                          # Prepended to take precedence
  │   └── initializers/
  │       └── tenanting/
  │           ├── tenant_resolver.rb         # Path-based tenant resolution
  │           ├── active_storage.rb          # Fix attachment URLs with script_name
  │           ├── turbo.rb                   # Fix Turbo broadcasts from jobs
  │           ├── logging.rb                 # Tenant ID in logs
  │           └── default_tenant.rb          # Dev console convenience
  ├── db/
  │   └── untenanted_migrate/
  ├── lib/
  │   └── sabha/
  │       └── saas/
  │           └── engine.rb
  └── sabha-saas.gemspec
  ```
- [x] Create `saas/lib/sabha/saas/engine.rb`
  ```ruby
  module Sabha
    module Saas
      class Engine < ::Rails::Engine
        # Non-isolated engine - extends Sabha, doesn't namespace
        engine_name "sabha_saas"

        # Disable automatic route loading - we define routes inline in initializer
        paths["config/routes.rb"] = []

        # Add SaaS paths to autoload
        initializer "sabha_saas.autoload_paths", before: :set_autoload_paths do |app|
          if Sabha.saas?
            app.config.autoload_paths << root.join("app/models")
            app.config.autoload_paths << root.join("app/controllers")
            app.config.autoload_paths << root.join("app/controllers/concerns")
            app.config.autoload_paths << root.join("app/helpers")
            app.config.autoload_paths << root.join("app/mailers")
            app.config.autoload_paths << root.join("app/channels/concerns")
          end
        end

        # Prepend SaaS routes to take precedence over core routes
        # These routes only match when OUTSIDE a workspace context (no tenant set)
        initializer "sabha_saas.routes", after: :add_routing_paths do |app|
          next unless Sabha.saas?

          app.routes.prepend do
            constraints(->(req) { ApplicationRecord.current_tenant.blank? }) do
              root to: "saas/landing#show", as: :saas_root
              resource :session, only: [ :new, :create, :destroy ], controller: "saas/sessions"
              resource :auth_code, only: [ :show, :create ], controller: "saas/auth_codes"
              resource :registration, only: [ :new, :create ], controller: "saas/registrations"
              resource :profile, only: [ :edit, :update ], controller: "saas/profiles"
              resources :workspaces, only: [ :index, :new, :create ], controller: "saas/workspaces"
              get "join/:code", to: "saas/workspaces#join", as: :join
              post "join/:code", to: "saas/workspaces#join"
            end
          end
        end

        # Load SaaS initializers, include helpers, etc.
      end
    end
  end
  ```
- [x] Create `saas/app/controllers/saas/base_controller.rb`
  ```ruby
  module Saas
    class BaseController < ActionController::Base
      # Inherits directly from ActionController::Base to bypass the core
      # ApplicationController's Authentication concern which tries to access
      # tenanted Session models.

      protect_from_forgery with: :exception
      include Saas::Authentication
      include SetCurrentRequest

      # Include core helpers for consistent UI
      helper ApplicationHelper
      helper TranslationsHelper

      # Require GlobalIdentity authentication by default
      require_authentication

      # Load workspaces for sidebar
      before_action :load_workspaces_for_sidebar

      layout "saas"
    end
  end
  ```
- [x] Create `saas/sabha-saas.gemspec`
- [x] Create `Gemfile.saas` that extends base Gemfile
  ```ruby
  eval_gemfile "Gemfile"
  gem "sabha-saas", path: "saas"
  ```
- [x] Create `lib/sabha.rb` with `Sabha.saas?` detection
- [x] Add `saas:enable` / `saas:disable` rake tasks
- [x] Update `.gitignore` for SaaS-specific files

### MVP-1: Core Infrastructure (in saas/ folder)

- [x] Add `activerecord-tenanted` gem to `Gemfile.saas`
  - **Note:** Using fork `ashwin47/activerecord-tenanted` branch `fix-rails-82-type-for-column-signature` until [upstream PR](https://github.com/basecamp/activerecord-tenanted/pull/XXX) is merged
  - Rails 8.2 changed `type_for_column` signature (rails/rails#54333), gem fork adds version check to skip the `Attributes` patch for Rails 8.2+
- [x] Create `saas/config/database.yml.saas` template with tenanted primary + untenanted databases
- [x] Create `saas/db/untenanted_migrate/` directory for untenanted DB migrations
- [x] Update `.gitignore` for workspace database files
- [x] Create `saas/app/models/untenanted_record.rb`
- [x] Create engine initializer to add `tenanted` macro to ApplicationRecord when SaaS enabled
- [x] Create `saas/lib/sabha/saas/path_rewriter.rb` middleware for path-based workspace resolution
  - Extracts 7+ digit workspace ID from path (e.g., `/1000001/rooms/general`)
  - Moves workspace prefix from `PATH_INFO` to `SCRIPT_NAME`
  - Stashes workspace ID in `env["sabha.workspace_id"]` for tenant resolver
- [x] Create `saas/config/initializers/tenanting/tenant_resolver.rb`
  - Configures middleware insertion: `PathRewriter` runs BEFORE `TenantSelector`
  - Simple lambda reads `env["sabha.workspace_id"]` for the gem's tenant resolver
  - `Current.workspace` is lazy-loaded when accessed (no before_action needed)
- [x] Create `saas/config/initializers/tenanting/active_storage.rb` - Fix attachment URLs
  - Sets `ActiveStorage::Current.url_options` with `script_name` in before_action
  - Without this, file uploads/downloads generate wrong URLs
  ```ruby
  ActiveStorage::Current.url_options = {
    protocol: request.protocol, host: request.host,
    port: request.port, script_name: request.script_name
  }
  ```
- [x] Create `saas/config/initializers/tenanting/turbo.rb` - Fix Turbo broadcasts from jobs
  - Prepends `Turbo::StreamsChannel` to inject `script_name` in renderer
  - Without this, background job broadcasts (message notifications) break
  ```ruby
  script_name = "/#{ApplicationRecord.current_tenant}"
  ApplicationController.renderer.new(script_name: script_name).render(...)
  ```
- [x] Create `saas/config/initializers/tenanting/logging.rb` - Tenant ID in logs
  - Adds tenant to structured logs for debugging
  - `before_action { logger.tagged(tenant: ApplicationRecord.current_tenant) }`
- [x] Create `saas/config/initializers/tenanting/default_tenant.rb` - Dev convenience
  - Sets default tenant in development for `rails console`
  - `config.active_record_tenanted.default_tenant = "1000001"`

### MVP-2: Untenanted Models (in saas/app/models/)

- [x] Create `saas/app/models/global_identity.rb` (untenanted DB)
  - Columns: `email_address`, `verified_at`, timestamps
  - **No password_digest** - OTP only for MVP
  - Unique index on email_address
  - `has_many :global_sessions, :auth_codes, :workspace_memberships` (no direct `:users` - accessed via workspace_membership)
- [x] Create `saas/app/models/auth_code.rb` (untenanted DB, like Fizzy)
  - Columns: `code`, `global_identity_id`, `purpose` (enum: sign_in/sign_up), `expires_at`, timestamps
  - 6-char code, 15-minute expiry
  - `belongs_to :global_identity`
  - `consume(code)` class method - returns global_identity, destroys auth_code
  ```ruby
  def self.consume(code)
    active.find_by(code: Code.sanitize(code))&.consume
  end
  def consume
    global_identity.tap { destroy }
  end
  ```
- [x] Create `saas/app/models/auth_code/code.rb` - Code generation & sanitization
  - Alphabet excludes ambiguous chars: `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (no O, I, L)
  - Auto-corrects typos: O→0, I→1, L→1
  - Strips invalid characters (handles pasted codes with dashes)
  ```ruby
  module AuthCode::Code
    CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".chars.freeze
    CODE_SUBSTITUTIONS = { "O" => "0", "I" => "1", "L" => "1" }.freeze

    def self.generate(length) = length.times.map { CODE_ALPHABET.sample }.join
    def self.sanitize(code)
      code.to_s.upcase
        .then { CODE_SUBSTITUTIONS.reduce(_1) { |r, (from, to)| r.gsub(from, to) } }
        .then { _1.gsub(/[^#{CODE_ALPHABET.join}]/, "") }
    end
  end
  ```
- [x] Create `saas/app/models/global_session.rb` (untenanted DB)
  - Columns: `token`, `global_identity_id`, `user_agent`, `ip_address`, `last_active_at`, `expires_at`, timestamps
  - Unique index on token
  - `belongs_to :global_identity`
- [x] Create `saas/app/models/workspace_membership.rb` (untenanted DB)
  - Columns: `global_identity_id`, `tenant` (string - workspace external_id), timestamps
  - Unique index on `[global_identity_id, tenant]`
  - Index on tenant
  - `belongs_to :global_identity, touch: true` (cache invalidation for workspace list)
  - `tenant` stores the workspace's external_id as a string (like Fizzy)
  - `user_id` column caches the User's ID for faster lookups
  - Helper methods to access tenant data:
  ```ruby
  def account_name
    ApplicationRecord.with_tenant(tenant) { Account.first&.name }
  rescue ActiveRecord::Tenanted::TenantDoesNotExistError
    nil
  end

  # Uses cached user_id for efficient lookup
  def user
    return nil if user_id.blank?
    ApplicationRecord.with_tenant(tenant) { User.find_by(id: user_id) }
  rescue ActiveRecord::Tenanted::TenantDoesNotExistError
    nil
  end

  def cache_user_id!(user_id)
    update_column(:user_id, user_id)
  end
  ```
- [x] Create `saas/app/models/workspace.rb` (untenanted DB)
  - Columns: `external_id` (bigint), `name`, `suspended_at`, timestamps
  - Add `slug` method returning `"/#{external_id}"`
  - `before_create :assign_external_id`
  - **Note**: Workspace has no settings - each workspace's `Account` model holds settings
- [x] Create `saas/app/models/workspace/external_id_sequence.rb` (untenanted DB)
  - Separate table for sequential ID generation with database locking (Fizzy pattern)
  - `Workspace::ExternalIdSequence.next` returns next ID
  - Uses `with_lock` and `increment!` for thread safety
  - Initial value: `Workspace.maximum(:external_id) || 0`
  - Seeds/fixtures use `ActiveRecord::FixtureSet.identify(name)` for deterministic IDs
- [x] Create all untenanted migrations in `saas/db/untenanted_migrate/`

### MVP-3: Core App Modifications (conditional on Sabha.saas?)

These changes to the core app only apply when SaaS mode is enabled:

- [x] Add `workspace_membership_id` column to `users` table (migration in core, column ignored in single-tenant)
- [x] Update `User` model with:
  ```ruby
  belongs_to :workspace_membership, optional: true
  has_one :global_identity, through: :workspace_membership, disable_joins: true
  ```
- [x] Update `Current.rb` with dual-mode support:
  ```ruby
  class Current < ActiveSupport::CurrentAttributes
    attribute :session, :user, :request
    attribute :global_session, :workspace_membership  # SaaS mode only

    delegate :host, :protocol, to: :request, prefix: true, allow_nil: true

    # Single-tenant: session sets user directly
    def session=(value)
      super
      self.user = value&.user unless Sabha.saas?
    end

    # SaaS: global_session sets workspace_membership
    def global_session=(value)
      super
      return if value.nil?
      if Sabha.saas? && ApplicationRecord.current_tenant.present?
        self.workspace_membership = value.global_identity
          &.workspace_memberships
          &.find_by(tenant: ApplicationRecord.current_tenant)
      end
    end

    def global_identity
      global_session&.global_identity
    end

    def user
      if Sabha.saas? && workspace_membership.present?
        workspace_membership.user
      else
        super
      end
    end

    def workspace
      return nil unless Sabha.saas? && ApplicationRecord.current_tenant.present?
      @workspace ||= Workspace.find_by(external_id: ApplicationRecord.current_tenant)
    end

    def account
      @account ||= Account.sole
    end

    def reset
      super
      @workspace = nil
      @account = nil
    end
  end
  ```
- [x] Core uses `app/controllers/concerns/set_current_request.rb` which sets `Current.request = request`
  - Request metadata (user_agent, ip_address) accessed via `request.user_agent`, `request.remote_ip`
  - Session creation passes these directly: `Session.create!(user_agent: request.user_agent, ip_address: request.remote_ip)`
  - SaaS's `BaseController` includes `SetCurrentRequest` (same as core)
- [x] Engine hooks into ApplicationRecord to add `tenanted` macro when saas enabled

### MVP-4: GlobalIdentity Authentication (in saas/ folder)

**Important:** SaaS has its own authentication system that operates outside workspace context. Core `ApplicationController` with its `Authentication` concern is still used for workspace-scoped controllers.

#### SaaS vs Core Auth

| Aspect | Core Auth | SaaS Auth |
|--------|-----------|-----------|
| Concern | `Authentication` (uses `Current.user`) | `Saas::Authentication` (uses `Current.global_identity`) |
| Cookie | `cookies.signed[:session_token]` | `cookies.signed[:global_session_token]` |
| Model | `Session` (tenanted) | `GlobalSession` (untenanted) |
| Controllers | `SessionsController`, `AuthTokensController` | `Saas::SessionsController`, `Saas::AuthCodesController` |
| Base class | `ApplicationController` | `Saas::BaseController` (inherits `ActionController::Base`) |

**Note:** Core auth is NOT "completely replaced" - it's still used for workspace-scoped controllers. SaaS auth only handles untenanted routes (login, signup, workspace selector).

#### Implementation Tasks

- [x] Create `saas/app/controllers/concerns/saas/authentication.rb`
  - Replaces core `Authentication` concern when SaaS enabled
  - `signed_in?` checks `Current.global_identity.present?`
  - `current_global_identity` - from cookie → GlobalSession → GlobalIdentity
  - `current_user` - from GlobalIdentity → User in Current.workspace (may be nil)
  - `require_authentication` - redirects to `/login` if no GlobalIdentity
  - `require_workspace` - redirects to `/workspaces` if no workspace
  - Uses `session[:global_identity_id]` instead of `session[:user_id]`
- [x] Create `saas/app/controllers/saas/sessions_controller.rb`
  - `require_untenanted_access` - login happens before tenant context
  - `require_unauthenticated_access except: :destroy`
  - `rate_limit to: 10, within: 3.minutes, only: :create`
  - OTP only (no password check, no `Current.account` dependency)
  - `create` - finds/creates GlobalIdentity, sends AuthCode
  - `destroy` - destroys GlobalSession, clears cookie
  - No `ensure_user_exists` check (GlobalIdentity can exist without User)
- [x] Create `saas/app/controllers/saas/auth_codes_controller.rb`
  - `require_untenanted_access`
  - `require_unauthenticated_access`
  - `rate_limit to: 10, within: 15.minutes, only: :create` (matches code expiry)
  - `show` - code entry form
  - `create` - validates code via `AuthCode.consume(code)`, creates GlobalSession
  - Returns global_identity directly, redirects to `after_authentication_url`
- [x] Create `saas/app/controllers/saas/registrations_controller.rb`
  - Creates GlobalIdentity (no workspace required)
  - Sends AuthCode for verification
- [x] Create `saas/app/mailers/auth_code_mailer.rb`
  - `code(auth_code)` - sends 6-char OTP code
- [x] Engine route overrides in `saas/config/routes.rb`
  ```ruby
  # These routes take precedence over core routes
  get "login", to: "saas/sessions#new"
  post "login", to: "saas/sessions#create"
  delete "logout", to: "saas/sessions#destroy"
  get "signup", to: "saas/registrations#new"
  post "signup", to: "saas/registrations#create"
  resource :session_auth_code, controller: "saas/auth_codes", only: [:show, :create]
  # FirstRunsController NOT mounted - no global first run in SaaS
  ```
- [x] Engine hooks to override Authentication concern
  ```ruby
  # saas/lib/sabha/saas/engine.rb
  initializer "saas.override_authentication" do
    ActiveSupport.on_load(:action_controller_base) do
      if Sabha.saas?
        # Remove core Authentication, add SaaS version
        include Saas::Authentication
      end
    end
  end
  ```
- [x] Handle login redirects with workspace context
  - Reuse `post_authenticating_url` pattern from core `Authentication` concern
  - Core already has `session[:return_to_after_authenticating]` + `safe_redirect_url?` check
  - After login, redirect to stored URL or `/{workspace_id}/` or `/workspaces`
  - `Saas::Authentication` should define `after_authentication_url` calling same pattern

### MVP-5: Workspace Context Fixes (conditional on saas?)

Apply lessons learned from v1 implementation. These fixes only matter when multi-tenancy is enabled:

- [x] Replace `ActiveRecord::Base` with `ApplicationRecord` in `app/models/message/rich_text_updater.rb`
- [x] Add `tenanted?` class method to non-AR GlobalID classes (when saas?)
  - `app/models/everyone.rb` - Added `self.tenanted?` returning `false`
- [x] Fix `after_create_commit` → `after_create` for workspace callbacks (when saas?)
  - `User#subscribe_to_emails` - Already uses `after_create`
- [x] Form routes work correctly - Rails uses `script_name` when generating URLs, no explicit `url:` needed
- Mailkick subtenant config deferred to v2 (works fine in self-hosted mode)

### MVP-6: ActionCable (conditional on saas?)

- [x] **Use gem's built-in `around_command :with_tenant`** - The `activerecord-tenanted` gem automatically wraps all channel commands in tenant context via `CableConnection::Base`
- [x] **Update connection to use `current_tenant`** - Changed `app/channels/application_cable/connection.rb` to call `super` (gem sets tenant from resolver) and use `current_tenant` instead of custom `workspace_id`
- [x] **Create `TenantContext` concern** - `saas/app/channels/concerns/tenant_context.rb` provides `with_tenant_context` helper for explicit DB operation wrapping
- [x] **Update channels to use tenant context** - `RoomChannel`, `PresenceChannel`, `TypingNotificationsChannel` wrap DB operations in `with_tenant_context`
- [x] **Fix Turbo broadcasts** - `saas/config/initializers/tenanting/turbo.rb` overrides `render_format` to inject `script_name`
- [x] **Stream isolation via GlobalID** - `stream_for model` is automatically tenant-scoped because GlobalID includes tenant parameter. No separate `workspace_stream` helper needed.
- [x] **User-scoped channels** - Channels like `UserUnreadRoomsChannel` use `stream_for current_user` which includes tenant in GlobalID
- [x] **Fix `User#close_remote_connections`** - Includes `current_tenant` filter in SaaS mode:
  ```ruby
  if Sabha.saas? && ApplicationRecord.current_tenant.present?
    ActionCable.server.remote_connections.where(
      current_tenant: ApplicationRecord.current_tenant,
      current_user: self
    ).disconnect
  end
  ```
- [x] **Fix thread pools to capture/restore tenant context** - `lib/web_push/pool.rb` now captures tenant before posting to thread pool and restores it inside the thread
  - **Note**: Basic implementation done, thorough review deferred to v2-8

### MVP-7: Workspace Selector & Tenanting Helpers (in saas/ folder)

- [x] Create `saas/app/helpers/tenanting_helper.rb`
  - `tenanted_action_cable_meta_tag` - generates ActionCable URL with workspace prefix
  - `untenanted_url(route_name, *args)` - generates URL without workspace prefix
  - `untenanted_path(route_name, *args)` - generates path without workspace prefix
- [x] Create `saas/app/helpers/workspace_selector_helper.rb`
  - `show_workspace_selector?` - shows when user has 1+ workspaces (configurable via `WORKSPACE_SELECTOR_MIN`)
  - `user_workspaces` - returns workspace data for current global_identity
  - Generate workspace URLs using `script_name: workspace.slug`
- [x] Create `saas/app/views/shared/_workspace_selector.html.erb` partial
  - User avatar at top (shows email initial for GlobalIdentity)
  - Workspace list with active indicator
  - "+" button links to `/workspaces/new` via `untenanted_path`
- [x] Create `saas/app/assets/stylesheets/workspace_selector.css` styles
  - Slack/Discord-style design: 72px width, rounded squares with hover animation
  - Dark mode support via CSS custom properties and `[data-theme]` attribute
  - Mobile responsive (hidden on small screens)
- [x] Engine injects workspace selector into main layout when saas enabled
  - Added `sabha_saas.assets` initializer to add SaaS stylesheets to asset paths
  - Added `sabha_saas.view_paths` initializer to add SaaS views
  - Added `sabha_saas.helpers` initializer to include WorkspaceSelectorHelper and TenantingHelper
  - Layout conditionally renders `shared/workspace_selector` partial
- [x] Add body class `.app-with-workspaces` when selector is shown
  - Added `workspace_selector_body_class` helper to ApplicationHelper
  - CSS applies `margin-left: 72px` to body for layout adjustment

#### Workspace Selector Enhancements (PR #63)

- [x] **Drag-to-reorder workspaces**
  - Added `position` column to `WorkspaceMembership` model
  - Created `workspace_sortable_controller.js` Stimulus controller
  - Created `Saas::WorkspaceMembershipsController#reorder` endpoint
  - Uses HTML5 drag-and-drop (disabled on touch devices)
  - Race condition protection for rapid reordering
- [x] **Discord-style layout improvements**
  - Home button at top (links to workspace list)
  - Profile icon moved to footer (shows email initial)
  - Notification dot on profile when action required (unverified email)
  - Separator lines between sections
  - Improved icon contrast for better legibility
- [x] **Layout adjustments**
  - Hide sabha logo in SaaS mode (workspace selector replaces it)
  - Adjust nav positioning for workspace selector width
  - Remove 5vw left margin column in SaaS mode

### MVP-8: GlobalIdentity Registration (in saas/ folder)

- [x] Create `saas/app/controllers/saas/registrations_controller.rb`
  - `new` - signup form (email only)
  - `create` - creates GlobalIdentity or redirects existing to login, sends OTP
  - Route: `resource :registration, only: [:new, :create]`
  - Rate limited to 10 attempts per 3 minutes
- [x] Create `saas/app/controllers/saas/profiles_controller.rb`
  - `edit` / `update` - edit GlobalIdentity email
  - Changing email requires re-verification (marks as unverified, signs out)
  - Route: `resource :profile, only: [:edit, :update]`
- [x] Create/update views in `saas/app/views/saas/registrations/` and `saas/app/views/saas/profiles/`
  - Views use Sabha styling (panel, fieldset, btn classes)
  - Registration links to sign in, session links to registration
  - Profile allows email change with cancel option
- [x] Update login flow
  - Sessions controller already redirects to `workspaces_path` after authentication
  - Workspaces index shows user header with Profile/Sign out links
  - Empty state shows "Create workspace" button

### MVP-9: Workspace Management (in saas/ folder)

- [x] Create `saas/app/controllers/saas/workspaces_controller.rb`
  - `index` - list user's workspaces or empty state
  - `new` - create workspace form (name only)
  - `create` - create Workspace + database, redirect to `/{id}/`
  - `join` - join with code, allows unauthenticated access
- [x] Create views in `saas/app/views/saas/workspaces/`
  - `index.html.erb` - workspace list with empty state
  - `new.html.erb` - create workspace form
  - `join.html.erb` - shows workspace name, login/signup for unauthenticated users
- [x] Implement `Workspace.create_with_database!`
  - Creates Workspace record in untenanted DB (gets next ID starting at 1000001)
  - Creates workspace database with `ApplicationRecord.create_tenant(id)`
  - Creates Account record in new workspace DB (for settings)
  - Creates WorkspaceMembership
  - Returns workspace for redirect to `/{workspace_id}/`
- [x] **Join flow implemented in WorkspacesController#join**
  - `allow_unauthenticated_access only: :join` - anyone with code can view
  - Route: `GET/POST /join/:code` (not per-tenant, code is globally unique lookup)
  - `Workspace.find_by_join_code(code)` - iterates workspaces to find matching code
  - Shows workspace name if valid, "Invalid invite link" if not
  - Unauthenticated users see login/signup options with `return_to` param
  - POST requires authentication, creates WorkspaceMembership
- [x] **Fix join code lookup** - `find_by_join_code` now uses `join_codes.active.exists?(code: code)` instead of comparing JoinCode object to string
- [x] **Untenanted URL helpers** - `saas/app/helpers/tenanting_helper.rb` adds `untenanted_url` and `untenanted_path` to generate URLs without workspace prefix
- [x] **Fix invite link generation** - Updated `accounts/_invite.html.erb` and `users/profiles/_invite_link.html.erb` to use `untenanted_url(:join, code)` in SaaS mode
- [x] **Handle return_to in auth flow** - Updated `Saas::SessionsController#new` and `Saas::AuthCodesController#show` to store `params[:return_to]` in session

### MVP-10: Background Jobs

- [x] Update jobs that process all users to iterate workspaces
  - `UnreadMentionsNotifierJob` - Now uses `ApplicationRecord.with_each_tenant` in SaaS mode
  - Other jobs (`BroadcastInboxThreadsJob`, `RoomUpdateBroadcastJob`, `Room::PushMessageJob`, `Bot::WebhookJob`) are event-triggered and work automatically via gem's job serialization
- [x] Verify job workspace serialization works (gem feature)
  - The gem automatically serializes `current_tenant` with jobs and restores it on `perform_now`
  - AR objects passed to jobs include tenant in their GlobalID
- [x] Fix thread pool workspace context in `WebPush::Pool`
  - Already implemented in MVP-6: captures tenant before thread pool post, restores inside thread via `with_tenant` helper

### MVP-11: Testing ✅

SaaS tests are located in `saas/test/` (separate from self-hosted tests in `test/`).

**Fixtures** (`saas/test/fixtures/`):
- [x] Create `global_identities.yml`
- [x] Create `global_sessions.yml`
- [x] Create `workspace_memberships.yml`
- [x] Create `workspaces.yml`
- [x] Create `auth_codes.yml`

**Test Helper** (`saas/test/test_helper.rb`):
- [x] SaasTestHelper module with fixture accessors
- [x] `sign_in_global_identity(identity)` helper with signed cookies
- [x] `workspace_get/post/patch/delete` helpers for workspace-scoped requests

**Model Tests** (`saas/test/models/`):
- [x] GlobalIdentity tests (verification, associations, scopes)
- [x] GlobalSession tests (token generation, expiration, associations)
- [x] Workspace tests (external_id, suspension, scopes)
- [x] WorkspaceMembership tests (associations, scopes)
- [x] AuthCode tests (code generation, expiration, consumption)

**Controller Tests** (`saas/test/controllers/saas/`):
- [x] Sessions controller (login, logout, auth code verification)
- [x] Registrations controller (signup flow)
- [x] Workspaces controller (list, create workspaces)
- [x] Profiles controller (edit global profile)
- [x] Landing controller (unauthenticated/authenticated landing)
- [x] AuthCodes controller (code verification)
- [x] Authentication concern tests

**CI Integration**:
- [x] Added `test-saas` job to `.github/workflows/test.yml`

**Running Tests**:
```bash
# Self-hosted tests
bin/rails test

# SaaS tests
SAAS=true BUNDLE_GEMFILE=Gemfile.saas bin/rails test saas/test/
```

### MVP-12: Development Setup ✅

- [x] Update `bin/setup` for multi-workspace
  - Runs `saas:setup` automatically in SaaS mode
  - Handles `--reset` flag properly for SaaS databases
- [x] Create `workspace:create[name,email]` rake task
  - Creates next workspace ID (1000002, etc.)
  - Returns workspace ID for use in URL
- [x] Create `workspace:destroy[id]` rake task
- [x] Create `workspace:list` rake task
- [x] Create `workspace:info[id]` rake task (bonus)
- [x] Create `saas:setup` rake task
  - Runs untenanted migrations
  - Creates default workspace (ID 1000001)
- [x] Create `saas:reset` rake task for full reset
- [x] Document development workflow in CLAUDE.md
  - Access landing: `http://localhost:3000/`
  - Access workspace: `http://localhost:3000/1000001/`

### MVP-13: Settings & Workspace Membership Management ✅

**Architecture:**
- Global `/settings` page for account management + workspace list
- Workspace-scoped `/{workspace_id}/settings` for leave/delete actions
- All users can access workspace settings through global settings page (not admin-only)

**Files Created:**
- `saas/app/controllers/saas/settings_controller.rb` - Global settings (email edit)
- `saas/app/controllers/saas/workspace_settings_controller.rb` - Workspace leave/delete
- `saas/app/views/saas/settings/show.html.erb` - Global settings view
- `saas/app/views/saas/workspace_settings/show.html.erb` - Workspace settings view
- `app/frontend/controllers/confirm_delete_controller.js` - Type-to-confirm Stimulus controller
- `saas/test/controllers/saas/settings_controller_test.rb` - Settings tests
- `saas/test/controllers/saas/workspace_settings_controller_test.rb` - Workspace settings tests

**Files Modified:**
- `saas/lib/sabha/saas/engine.rb` - Changed profile route to settings
- `saas/app/views/shared/_workspace_selector.html.erb` - Changed to gear icon for settings
- `saas/app/helpers/workspace_selector_helper.rb` - Removed unused profile_has_notifications
- `saas/app/assets/stylesheets/workspace_selector.css` - Icon sizing, removed notification CSS
- `config/routes.rb` - Added workspace_settings routes
- `saas/app/models/workspace.rb` - Added `last_administrator?`, `destroy_with_database!`
- `saas/app/models/workspace_membership.rb` - Added `leave!` method

**Files Deleted:**
- `saas/app/controllers/saas/profiles_controller.rb`
- `saas/app/views/saas/profiles/edit.html.erb`
- `saas/test/controllers/saas/profiles_controller_test.rb`

- [x] **Global Settings Page (`/settings`)**
  - [x] Email editing with re-verification flow
  - [x] List of user's workspaces with links to workspace settings
  - [x] Sign out link
  - [x] Create workspace button
  - [x] Gear icon in workspace selector footer

- [x] **User can leave a workspace**
  - [x] Leave option in workspace settings (`/{workspace_id}/settings`)
  - [x] `WorkspaceMembership#leave!` deactivates User and destroys membership
  - [x] Redirect to workspace selector after leaving
  - [x] Prevent last administrator from leaving (shows disabled button with explanation)
  - [x] Confirmation dialog via Turbo confirm
  - [x] Tests for leave flow

- [x] **Admin can delete a workspace**
  - [x] Delete option in workspace settings (admin only)
  - [x] Type workspace name to confirm (Stimulus controller)
  - [x] `Workspace#destroy_with_database!` destroys tenant DB and record
  - [x] Redirect to workspace selector after deletion
  - [x] Tests for delete flow

---

## v1 Phase

**Goal**: Admin dashboard, workspace management, production deployment.

### v1-1: Super Admin

- [ ] Create `SuperAdmin` model in untenanted DB
- [ ] Create `Admin::SessionsController`
- [ ] Create admin login page
- [ ] Implement admin session management (separate from workspace)
- [ ] Create `Admin::BaseController` with authentication

### v1-2: Admin Dashboard

- [ ] Create `Admin::DashboardController`
- [ ] Create dashboard view with stats
  - Total workspaces
  - Total users across workspaces
  - Total messages
  - Recent signups
  - Active workspaces

### v1-3: WorkspaceStats

- [ ] Create `WorkspaceStats` model in untenanted DB
- [ ] Create `WorkspaceStatsAggregationJob`
- [ ] Schedule with rufus-scheduler (hourly)
- [ ] Display in admin dashboard

### v1-4: Workspace Management

- [ ] Create `Admin::WorkspacesController` (CRUD)
- [ ] Workspace list view with search/filter
- [ ] Workspace detail view with stats
- [ ] Workspace edit (name only, slug immutable)
- [ ] Workspace suspend/unsuspend
- [ ] Workspace delete with confirmation

### v1-5: Suspended Workspace Handling

- [ ] Update workspace resolver to check `suspended_at`
- [ ] Create suspended workspace error page
- [ ] Return 403 for suspended workspaces

### v1-6: Production Deployment

- [ ] Update `config/deploy.yml` for Kamal
- [ ] Configure volume mounts for workspace databases
- [ ] Standard SSL (no wildcard needed with path-based routing)
- [ ] Document backup/restore procedures

### v1-7: Security Audit

- [ ] Test cross-workspace data isolation
- [ ] Test ActionCable broadcast isolation
- [ ] Test Active Storage workspace prefixing
- [ ] Test cache key isolation
- [ ] Review all `without_workspace` usages

---

## v2 Phase (Future)

**Goal**: Billing, usage limits, advanced SaaS features.

Note: SaaS folder structure is now created in MVP. v2 extends it.

### v2-1: Licensing

- [ ] Add O'Saasy or similar license
- [ ] Update README with license terms
- [ ] Add license headers to files

### v2-2: Billing Integration

- [ ] Add `stripe` gem to `Gemfile.saas`
- [ ] Create `saas/app/models/subscription.rb`
- [ ] Create `saas/app/models/plan.rb`
- [ ] Create `saas/app/controllers/saas/billing_controller.rb`
- [ ] Webhook handlers for Stripe events

### v2-3: Usage Limits

- [ ] Track usage per workspace (messages, users, storage)
- [ ] Enforce limits based on plan
- [ ] UI for approaching/exceeded limits

### v2-4: Analytics/Metrics

- [ ] Create `saas/app/models/workspace_usage.rb`
- [ ] Dashboard for workspace owners
- [ ] Aggregated analytics for super admin

### v2-5: CI/CD Split ✅

- [x] Updated `.github/workflows/test.yml` with two parallel jobs:
  - `test` job: Self-hosted tests (`bin/rails test`)
  - `test-saas` job: SaaS tests (`bin/rails test saas/test/`)
- [x] Both test suites run in CI on push to main and PRs

### v2-6: Slack Import Support

- [ ] Fix `ActiveRecord::Base.transaction` → `ApplicationRecord.transaction` in `app/services/slack_importer.rb`
- [ ] Test Slack import works correctly within workspace context
- [ ] Consider admin-only access to Slack import in SaaS mode

### v2-7: Mailkick Multi-tenancy

- [ ] Configure Mailkick::Subscription as subtenant of ApplicationRecord
- [ ] Use `to_prepare` callback for code reload support
- [ ] Test email subscription/unsubscription across workspaces

### v2-8: WebPush Multi-tenancy Review

- [ ] Review WebPush::Pool thread context handling for edge cases
- [ ] Test web push notifications work correctly across workspaces
- [ ] Verify subscription invalidation runs in correct tenant context
- [ ] Consider whether `invalid_subscription_handler` needs tenant-aware lookup
- [ ] Test concurrent notifications to users in different workspaces

**Note**: Basic tenant capture/restore implemented in MVP-6, but needs thorough testing and potential refinement.

---

## Known Gotchas & Edge Cases

### Critical (Must Fix)

#### 1. ActionCable Remote Connections Need Workspace ✅ FIXED

```ruby
# In app/models/user.rb - close_remote_connections method
def close_remote_connections(reconnect: false)
  if Sabha.saas? && ApplicationRecord.current_tenant.present?
    ActionCable.server.remote_connections.where(
      current_tenant: ApplicationRecord.current_tenant,
      current_user: self
    ).disconnect reconnect: reconnect
  else
    ActionCable.server.remote_connections.where(current_user: self).disconnect reconnect: reconnect
  end
end
```

**Status**: Already implemented correctly in `app/models/user.rb:345-353`

#### 2. Replace ActiveRecord::Base with ApplicationRecord

All raw SQL and transactions must use `ApplicationRecord`:

```ruby
# WRONG - causes NoWorkspaceError
ActiveRecord::Base.connection.execute(sql)
ActiveRecord::Base.transaction { ... }

# CORRECT
ApplicationRecord.connection.execute(sql)
ApplicationRecord.transaction { ... }
```

**Files to check**:
- `app/models/message/rich_text_updater.rb` ✅ Fixed
- `app/services/slack_importer.rb` (deferred to v2 - Slack import not in MVP)

#### 3. Thread Pools Lose Workspace Context ✅ FIXED

Background thread pools (like WebPush delivery) lose workspace context. Fixed in `lib/web_push/pool.rb`:

```ruby
def deliver_later(payload, subscription)
  # Capture tenant BEFORE entering thread pool
  tenant = current_tenant

  delivery_pool.post do
    # Restore tenant INSIDE thread
    deliver(notification, subscription_id, tenant)
  end
end

def current_tenant
  if defined?(ApplicationRecord) && ApplicationRecord.respond_to?(:current_tenant)
    ApplicationRecord.current_tenant
  end
end

def with_tenant(tenant, &block)
  if tenant.present? && defined?(ApplicationRecord) && ApplicationRecord.respond_to?(:with_tenant)
    ApplicationRecord.with_tenant(tenant, &block)
  else
    yield
  end
end
```

**Location**: `lib/web_push/pool.rb` - now captures tenant before thread pool post and restores it inside the thread.

**Note**: Basic implementation done in MVP-6. Thorough testing and review deferred to v2-8.

#### 4. Non-AR Models Need `tenanted?` Class Method

Plain Ruby classes using GlobalID need this:

```ruby
class Everyone
  include GlobalID::Identification

  def self.tenanted?
    false  # Required by activerecord-tenanted gem
  end
end
```

**Files to check**: Any class that uses `GlobalID::Identification`

#### 5. ActionCable Broadcasts Are Tenant-Scoped via GlobalID ✅ AUTOMATIC

The `activerecord-tenanted` gem automatically handles tenant scoping for ActionCable:

**Model-based streams (preferred)** - Use `stream_for` which uses GlobalID with tenant param:
```ruby
# Channels
stream_for current_user, :inbox_mentions  # GlobalID includes tenant

# Broadcasts
broadcast_to user, :inbox_mentions, target: "inbox", partial: "..."
```

**The gem automatically:**
- Includes `?tenant=1000001` in all GlobalID URLs
- Validates tenant on locate (raises `WrongTenantError` if mismatch)
- Wraps channel commands in `with_tenant` context

**TenantContext concern** - For explicit DB operations in channels:
```ruby
# saas/app/channels/concerns/tenant_context.rb
def with_tenant_context(&block)
  if Sabha.saas? && current_tenant.present?
    ApplicationRecord.with_tenant(current_tenant, &block)
  else
    yield
  end
end
```

#### 5b. ActionCable Connection Must Use Gem's `current_tenant`

The `activerecord-tenanted` gem provides `around_command :with_tenant` that automatically wraps all channel commands in tenant context. To use it:

```ruby
# app/channels/application_cable/connection.rb
def connect
  super if Sabha.saas?  # Let gem set current_tenant from tenant_resolver
  # ... then do custom auth using current_tenant
end
```

**Key**: The connection must call `super` to let the gem set `current_tenant`. Don't use a custom `workspace_id` identifier.

#### 5c. Join Code Lookup Must Compare Strings

`Account#join_code` returns a `JoinCode` object, not a string:

```ruby
# WRONG - compares object to string, always false
account.join_code == code_string

# CORRECT - query for matching code
account.join_codes.active.exists?(code: code_string)
```

#### 5d. Join URLs Must Be Untenanted

Join links should NOT include the workspace prefix since they're accessed outside workspace context:

```ruby
# WRONG - generates /1000002/join/abc123 (won't match route)
join_url(code)

# CORRECT - generates /join/abc123
untenanted_url(:join, code)
```

Use `untenanted_url` helper from `TenantingHelper` for URLs that need to work outside workspace context.

### Medium Priority

#### 6. Mailkick Subscription Subworkspace Config

Must use `to_prepare` (not `after_initialize`) for code reload:

```ruby
# config/initializers/mailkick.rb
Rails.application.config.to_prepare do
  Mailkick::Subscription.subtenant_of "ApplicationRecord"
end
```

#### 7. after_create_commit Runs Outside Workspace Context

```ruby
# WRONG - NoWorkspaceError because callback runs after transaction
after_create_commit :subscribe_to_emails

# CORRECT - runs inside transaction with workspace context
after_create :subscribe_to_emails
```

**Location**: `app/models/user.rb`

#### 8. Form Routes with Workspace Model

```erb
<%# WRONG - looks for workspace_path because @account is a Workspace %>
<%= form_with model: @account do |f| %>

<%# CORRECT - explicit route %>
<%= form_with model: @account, url: account_path do |f| %>
```

**Files to check**: Any form using `Current.account` or `Current.workspace`

#### 9. ~~Cookie Domain in Tests~~ (N/A - Path-Based Routing)

Not needed with path-based routing - all requests are same-origin.
Cookies work normally without special domain configuration.

#### 10. Background Jobs Must Iterate Workspaces

Jobs that process all users must iterate over all workspaces:

```ruby
def perform
  ApplicationRecord.with_each_workspace do
    User.active.find_each { |user| ... }
  end
end
```

**Location**: `app/jobs/unread_mentions_notifier_job.rb`

### Low Priority

#### 11. Workspace Settings in JSON Column

```ruby
# Reading
workspace.raw_settings&.dig("auth_method")
workspace.settings.restrict_room_creation_to_administrators?

# Writing
workspace.update!(settings: existing_settings.merge(new_settings))
```

#### 12. Test Fixtures Need GlobalIdentity References

```yaml
# test/fixtures/users.yml
david:
  workspace_membership: david_workspace_membership  # Must reference workspace_memberships.yml
  email_address: david@37signals.com
  ...
```

---

## File Reference

### New Files in saas/ Folder (Rails Engine)

```
saas/
├── app/
│   ├── controllers/
│   │   └── saas/
│   │       ├── base_controller.rb           # Base for SaaS controllers (inherits ActionController::Base)
│   │       ├── sessions_controller.rb       # GlobalIdentity login (handles return_to param)
│   │       ├── auth_codes_controller.rb     # OTP code verification (handles return_to param)
│   │       ├── registrations_controller.rb  # Signup flow
│   │       ├── settings_controller.rb       # Global settings (email edit + workspace list)
│   │       ├── workspace_settings_controller.rb  # Workspace leave/delete
│   │       ├── landing_controller.rb        # Landing page
│   │       └── workspaces_controller.rb     # Workspace CRUD + join flow
│   ├── controllers/concerns/
│   │   └── saas/
│   │       └── authentication.rb            # GlobalIdentity auth (uses cookies.signed[:global_session_token])
│   ├── channels/concerns/
│   │   └── tenant_context.rb                # with_tenant_context helper only
│   ├── models/
│   │   ├── untenanted_record.rb             # Base for untenanted models
│   │   ├── global_identity.rb               # Global user identity
│   │   ├── global_session.rb                # Cross-workspace session
│   │   ├── auth_code.rb                    # OTP codes for auth
│   │   ├── workspace.rb                     # Workspace registry + find_by_join_code
│   │   └── workspace_membership.rb          # GlobalIdentity-workspace link
│   ├── helpers/
│   │   ├── tenanting_helper.rb              # tenanted_action_cable_meta_tag, untenanted_url/path
│   │   └── workspace_selector_helper.rb     # Workspace selector logic
│   ├── views/
│   │   ├── layouts/
│   │   │   └── saas.html.erb                # SaaS layout (untenanted pages)
│   │   └── saas/
│   │       ├── sessions/
│   │       ├── auth_codes/
│   │       ├── landing/
│   │       └── workspaces/
│   │           └── join.html.erb            # Join page with login/signup for unauthenticated
│   └── assets/stylesheets/
│       └── workspace_selector.css
├── config/
│   ├── routes.rb                            # SaaS-only routes (join at /join/:code)
│   └── initializers/
│       └── tenanting/
│           ├── tenant_resolver.rb           # Path-based tenant resolution
│           ├── active_storage.rb            # Fix attachment URLs
│           ├── turbo.rb                     # Fix Turbo broadcasts (injects script_name)
│           ├── logging.rb                   # Tenant ID in logs
│           └── default_tenant.rb            # Dev console convenience
├── db/
│   └── untenanted_migrate/                  # Untenanted DB migrations
│       ├── YYYYMMDD_create_global_identities.rb
│       ├── YYYYMMDD_create_global_sessions.rb
│       ├── YYYYMMDD_create_auth_codes.rb
│       ├── YYYYMMDD_create_workspaces.rb
│       └── YYYYMMDD_create_workspace_memberships.rb
├── lib/
│   └── sabha/
│       └── saas/
│           ├── engine.rb                    # Rails engine setup
│           └── path_rewriter.rb             # Middleware to extract workspace from path
└── sabha-saas.gemspec
```

### New Files in Core App

```
lib/
└── sabha.rb                    # Sabha.saas? detection

Gemfile.saas                       # eval_gemfile "Gemfile" + SaaS deps

db/migrate/
└── YYYYMMDD_add_workspace_membership_id_to_users.rb  # Column for linking to WorkspaceMembership
```

### Core App Files to Modify (conditionally when saas?)

```
app/models/
├── user.rb                        # Add workspace_membership_id (optional), fix callbacks
├── current.rb                     # Add workspace method (returns nil if not saas)
└── everyone.rb                    # Add tenanted? method

app/channels/
├── application_cable/
│   ├── connection.rb              # ✅ Call super to use gem's current_tenant, custom SaaS auth
│   └── channel.rb                 # ✅ Include TenantContext concern (when saas?), fallback helpers
├── room_channel.rb                # ✅ Use with_tenant_context in find_room
├── presence_channel.rb            # ✅ Use with_tenant_context + workspace_broadcast
├── typing_notifications_channel.rb # ✅ Use with_tenant_context in start/stop
├── room_list_channel.rb           # ✅ Use workspace_stream for string streams
├── read_rooms_channel.rb          # ✅ Use workspace_stream for string streams
├── user_unread_rooms_channel.rb   # ✅ Use workspace_stream for string streams
├── user_involvements_channel.rb   # ✅ Use workspace_stream for string streams
└── unread_notifications_channel.rb # ✅ Use workspace_stream for string streams

app/models/
├── membership.rb                  # Broadcasts to user-scoped channels
├── room.rb                        # Broadcasts room updates
└── message/broadcasts.rb          # ✅ Uses broadcast_append_to, broadcast_to with models (auto tenant-scoped via GlobalID)

app/views/
├── accounts/_invite.html.erb      # ✅ Use untenanted_url for join links (when saas?)
├── users/profiles/_invite_link.html.erb # ✅ Use untenanted_url for join links (when saas?)
└── layouts/application.html.erb   # ✅ Use tenanted_action_cable_meta_tag (when saas?)

app/services/
└── slack_importer.rb              # v2: Use ApplicationRecord (Slack import deferred)

lib/web_push/
└── pool.rb                        # ✅ Fixed thread pool context (captures/restores tenant)

app/jobs/
└── unread_mentions_notifier_job.rb # Iterate workspaces (when saas?)

config/
└── initializers/mailkick.rb       # Subtenant config (when saas?)
```

### Test Files (saas/ folder)

```
saas/test/
├── fixtures/
│   ├── global_identities.yml       # ✅ alice, bob, unverified, admin
│   ├── global_sessions.yml         # ✅ alice_session, bob_session, expired_session
│   ├── workspaces.yml              # ✅ acme, shared, suspended
│   ├── workspace_memberships.yml   # ✅ Membership associations
│   └── auth_codes.yml             # ✅ alice_signin, unverified_signup, expired_link
├── models/
│   ├── global_identity_test.rb     # ✅ Verification, associations, scopes
│   ├── global_session_test.rb      # ✅ Token generation, expiration
│   ├── workspace_test.rb           # ✅ External ID, suspension, scopes
│   ├── workspace_membership_test.rb # ✅ Associations, scopes
│   └── auth_code_test.rb          # ✅ Code generation, consumption, expiration
├── controllers/
│   └── saas/
│       ├── authentication_test.rb        # ✅ Authentication concern tests
│       ├── sessions_controller_test.rb   # ✅ Login, logout, verification
│       ├── registrations_controller_test.rb # ✅ Signup flow
│       ├── workspaces_controller_test.rb # ✅ Workspace list, create
│       ├── settings_controller_test.rb   # ✅ Global settings (email edit)
│       ├── workspace_settings_controller_test.rb # ✅ Workspace leave/delete
│       ├── landing_controller_test.rb    # ✅ Landing page
│       └── auth_codes_controller_test.rb # ✅ Code verification
└── test_helper.rb                  # ✅ SaasTestHelper with signed cookie handling
```

---

## Testing Configuration

### How activerecord-tenanted Configures Tests

The gem automatically prepends test helpers when `connection_class` is set:

| Test Type | What Gem Does |
|-----------|---------------|
| `ActiveSupport::TestCase` | Sets `current_tenant` to `default_tenant`, handles parallel workers |
| `ActionDispatch::IntegrationTest` | Sets `host` to `{tenant}.example.com` |
| `ActionDispatch::IntegrationSession` | Wraps HTTP verbs in `without_tenant` block |
| `ActionDispatch::SystemTestCase` | Sets `default_url_options[:host]` with tenant |
| `ActiveRecord::Fixtures` | Handles transactional fixtures per tenant |
| `ActiveJob::TestCase` | Wraps `perform_enqueued_jobs` in `without_tenant` |
| `ActionCable::Connection::TestCase` | Sets `HTTP_HOST` with tenant |

### Sabha Test Modes

**Two test suites needed:**

1. **Self-hosted tests** (`bin/rails test`)
   - No tenant context
   - Uses existing Sabha fixtures
   - Tests password auth, single Account
   - `Sabha.saas?` returns `false`

2. **SaaS tests** (`SAAS=true bin/rails test`)
   - With tenant context
   - Uses SaaS fixtures (GlobalIdentity, WorkspaceMembership, Workspace)
   - Tests auth code auth, multi-workspace
   - `Sabha.saas?` returns `true`

### Test Helper Configuration

```ruby
# test/test_helper.rb (updated)
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  fixtures :all
  include ActiveJob::TestHelper
  include SessionTestHelper, MentionTestHelper, TurboTestHelper

  setup do
    ActionCable.server.pubsub.clear
    ActionController::Base.cache_store.clear  # Clear rate limit store
  end
end

# Self-hosted mode: no tenant modifications needed
# SaaS mode: gem handles tenant setup automatically
```

```ruby
# saas/test/test_helper.rb
require_relative "../../test/test_helper"

# Set default tenant for SaaS tests (path-based, 7+ digits)
Rails.application.config.active_record_tenanted.default_tenant =
  ActiveRecord::FixtureSet.identify("test_workspace").to_s  # e.g., "1234567"

# Load SaaS-specific fixtures
ActiveSupport::TestCase.class_eval do
  fixtures :global_identities, :global_sessions, :workspaces, :workspace_memberships
end
```

### Integration Test Setup (Path-Based Tenanting)

```ruby
# saas/test/integration_test_helper.rb
class ActionDispatch::IntegrationTest
  setup do
    # For path-based tenanting, set script_name instead of host
    integration_session.default_url_options[:script_name] =
      "/#{ApplicationRecord.current_tenant}"
  end
end
```

### System Test Setup

```ruby
# saas/test/application_system_test_case.rb
require "test_helper"
require_relative "../../test/application_system_test_case"

class SaasSystemTestCase < ApplicationSystemTestCase
  setup do
    # Path-based tenanting for system tests
    self.default_url_options[:script_name] = "/#{ApplicationRecord.current_tenant}"
  end
end
```

### Running Tests

```bash
# Self-hosted mode (default)
bin/rails test
bin/rails test:system

# SaaS mode (requires Gemfile.saas for activerecord-tenanted gem)
SAAS=true BUNDLE_GEMFILE=Gemfile.saas bin/rails test saas/test/

# Single SaaS test file
SAAS=true BUNDLE_GEMFILE=Gemfile.saas bin/rails test saas/test/models/workspace_test.rb

# CI runs both suites in parallel jobs (see .github/workflows/test.yml)
```

### Fixtures Strategy

**Self-hosted fixtures** (`test/fixtures/`):
- `users.yml` - Users with password_digest
- `accounts.yml` - Single Account
- `rooms.yml`, `messages.yml`, etc.

**SaaS fixtures** (`saas/test/fixtures/`):
- `global_identities.yml` - Global identities with email
- `global_sessions.yml` - Session tokens for global identities
- `workspaces.yml` - Multiple workspaces with external_id
- `workspace_memberships.yml` - Links global_identities to workspaces

**Shared fixtures** (both modes use):
- `rooms.yml`, `messages.yml`, `boosts.yml`, etc. (per-tenant data)

### Key Test Patterns

```ruby
# SaaS: Test cross-workspace isolation
test "user cannot access other workspace's rooms" do
  global_identity = global_identities(:alice)
  workspace_a = workspaces(:workspace_a)
  workspace_b = workspaces(:workspace_b)
  room_in_b = rooms(:room_in_workspace_b)

  sign_in_as global_identity, workspace: workspace_a

  get room_path(room_in_b, script_name: workspace_b.slug)
  assert_response :not_found  # or redirect to workspace selector
end

# SaaS: Test job runs in correct tenant
test "notification job runs in message's tenant" do
  message = messages(:hello)
  tenant = message.tenant

  MessageNotificationJob.perform_later(message)

  perform_enqueued_jobs

  # Assert job ran in correct tenant
  assert_equal tenant, ApplicationRecord.current_tenant
end

# Self-hosted: Test works without tenant
test "self-hosted login works" do
  user = users(:alice)
  post session_path, params: { email: user.email_address, password: "secret" }
  assert_redirected_to root_path
end
```

---

## Testing Checklist

### Unit Tests

- [ ] GlobalIdentity model validations
- [ ] GlobalSession token generation
- [ ] WorkspaceMembership uniqueness per tenant
- [ ] Workspace slug validation
- [ ] Current.workspace resolution (nil in self-hosted)
- [ ] Current.user (attribute in self-hosted, delegate in SaaS)
- [ ] AuthCode code generation and sanitization
- [ ] AuthCode.consume returns global_identity

### Integration Tests

- [ ] Auth code login flow (SaaS)
- [ ] Password login flow (self-hosted)
- [ ] GlobalSession cookie works across workspace paths (SaaS)
- [ ] User created from global_identity on first workspace visit
- [ ] Workspace selector shows correct workspaces
- [ ] Workspace creation flow
- [ ] Join code redemption
- [ ] Return URL after login with tenant prefix
- [ ] Rate limiting on login endpoints

### System Tests

- [ ] Full signup to first message flow (SaaS)
- [ ] Self-hosted first-run to first message flow
- [ ] Workspace switching
- [ ] ActionCable isolation between workspaces
- [ ] Turbo broadcasts work in both modes
- [ ] File upload/download URLs correct
- [ ] Real-time presence across workspaces

---

## Development Commands

```bash
# Run with specific tenant/workspace (use numeric ID)
ARTENANT=1000001 bin/rails console
ARTENANT=1000001 bin/rails db:migrate

# List workspaces
bin/rails workspace:list

# Create new workspace (returns ID like 1000002)
bin/rails workspace:create[name]

# Delete workspace
bin/rails workspace:destroy[1000001]

# Run tests
bin/rails test

# Access in browser
# Landing page: http://localhost:3000/
# Workspace 1000001: http://localhost:3000/1000001/
# Workspace 1000002: http://localhost:3000/1000002/
```
