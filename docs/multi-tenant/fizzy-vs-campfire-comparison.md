# Fizzy vs Campfire-CE Multi-Tenancy Comparison

A detailed comparison of multi-tenancy implementations between Fizzy (37signals) and Campfire-CE with the `activerecord-tenanted` gem.

**Scope:** This comparison covers MVP-0 through MVP-9 implementation phases:
- MVP-0: SaaS Folder Structure
- MVP-1: Core Infrastructure
- MVP-2: Untenanted Models
- MVP-3: Core App Modifications
- MVP-4: GlobalIdentity Authentication
- MVP-5: Workspace Context Fixes
- MVP-6: ActionCable
- MVP-7: Workspace Selector & Tenanting Helpers
- MVP-8: GlobalIdentity Registration
- MVP-9: Workspace Management

## Architecture Overview

| Aspect | Fizzy | Campfire-CE |
|--------|-------|-------------|
| **Database Strategy** | Single MySQL, account-scoped queries | Per-workspace SQLite databases |
| **Tenancy Model** | `Account` as tenant, `Current.account` scoping | `Workspace` registry + separate DBs via gem |
| **Tenant Identifier** | `external_account_id` (7+ digit integer) | `external_id` (7+ digit integer) |
| **URL Pattern** | Path-based: `/{account_slug}/...` | Path-based: `/{workspace_id}/...` |
| **Path Extraction** | Custom `AccountSlug::Extractor` middleware | Gem's `PathRewriter` + custom config |
| **Query Scoping** | Manual via `Current.account` in queries | Automatic via `tenanted` macro |
| **Global Identity** | `Identity` (same database) | `GlobalIdentity` (separate untenanted DB) |
| **Session Storage** | `Session` (same database) | `GlobalSession` (untenanted DB) |

---

## SaaS Detection

### Fizzy
```ruby
# lib/fizzy.rb
module Fizzy
  class << self
    def saas?
      return @saas if defined?(@saas)
      @saas = !!(((ENV["SAAS"] || File.exist?(File.expand_path("../tmp/saas.txt", __dir__))) && ENV["SAAS"] != "false"))
    end
  end
end
```

### Campfire-CE
```ruby
# lib/campfire.rb
module Campfire
  SAAS_MARKER = File.expand_path("../tmp/saas.txt", __dir__)

  class << self
    def saas?
      return @saas if defined?(@saas)
      @saas = (ENV["SAAS"] == "true" || File.exist?(SAAS_MARKER)) && ENV["SAAS"] != "false"
    end

    def configure_bundle
      if saas? && !ENV["BUNDLE_GEMFILE"]
        ENV["BUNDLE_GEMFILE"] = File.expand_path("../Gemfile.saas", __dir__)
      end
    end
  end
end
```

**Difference:** Campfire adds `configure_bundle` to auto-select `Gemfile.saas` before boot.

---

## Gemfile.saas

### Fizzy
```ruby
eval_gemfile "Gemfile"

gem "activeresource", require: "active_resource"
gem "stripe", "~> 18.0"
gem "queenbee", bc: "queenbee-plugin"          # Basecamp billing
gem "fizzy-saas", path: "saas"
gem "console1984", bc: "console1984"           # Audited console
gem "audits1984", bc: "audits1984"
gem "rails_structured_logging", bc: "rails-structured-logging"
gem "sentry-ruby", "sentry-rails"              # Error tracking
gem "yabeda-*"                                  # Metrics/telemetry
```

### Campfire-CE
```ruby
eval_gemfile "Gemfile"

gem "activerecord-tenanted", github: "ashwin47/activerecord-tenanted",
    branch: "fix-rails-82-type-for-column-signature"
gem "campfire-saas", path: "saas"
```

**Difference:** Fizzy includes billing (Stripe/Queenbee), auditing, and telemetry. Campfire-CE is minimal - just the tenanting gem and SaaS engine.

---

## Engine Structure

### Fizzy
```ruby
# saas/lib/fizzy/saas/engine.rb
module Fizzy
  module Saas
    class Engine < ::Rails::Engine
      Queenbee.host_app = Fizzy

      initializer "fizzy.saas.routes", after: :add_routing_paths do |app|
        app.routes.prepend do
          namespace :account do
            resource :billing_portal, only: :show
            resource :subscription { ... }
          end
        end
      end

      config.to_prepare do
        ::Account.include Account::Billing, Account::Limited
        ::Signup.prepend Fizzy::Saas::Signup
        ::ApplicationController.include Fizzy::Saas::Authorization::Controller
      end
    end
  end
end
```

### Campfire-CE
```ruby
# saas/lib/campfire/saas/engine.rb
module Campfire
  module Saas
    class Engine < ::Rails::Engine
      engine_name "campfire_saas"
      paths["config/routes.rb"] = []  # Disable auto-loading

      initializer "campfire_saas.prepend_routes", after: :add_routing_paths do |app|
        if Campfire.saas?
          saas_routes = root.join("config/routes.rb").to_s
          app.routes_reloader.paths.unshift(saas_routes)
        end
      end

      initializer "campfire_saas.migrations" do |app|
        if Campfire.saas?
          app.config.paths["db/migrate"] << root.join("db/untenanted_migrate").to_s
        end
      end

      config.to_prepare do
        if Campfire.saas?
          require_dependency Engine.root.join("app/controllers/concerns/saas/authentication")
        end
      end
    end
  end
end
```

**Difference:** Fizzy's engine focuses on billing/authorization extensions. Campfire's engine manages route prepending and untenanted migrations.

---

## Tenant Resolution

### Fizzy - Custom Middleware
```ruby
# config/initializers/tenanting/account_slug.rb
module AccountSlug
  PATTERN = /(\d{7,})/
  PATH_INFO_MATCH = /\A(\/#{AccountSlug::PATTERN})/

  class Extractor
    def call(env)
      request = ActionDispatch::Request.new(env)

      if request.path_info =~ PATH_INFO_MATCH
        # Move prefix from PATH_INFO to SCRIPT_NAME
        request.engine_script_name = request.script_name = $1
        request.path_info = $'.empty? ? "/" : $'
        env["fizzy.external_account_id"] = AccountSlug.decode($2)
      end

      if env["fizzy.external_account_id"]
        account = Account.find_by(external_account_id: env["fizzy.external_account_id"])
        Current.with_account(account) { @app.call env }
      else
        Current.without_account { @app.call env }
      end
    end
  end
end

Rails.application.config.middleware.insert_after Rack::TempfileReaper, AccountSlug::Extractor
```

### Campfire-CE - Gem Configuration
```ruby
# saas/config/initializers/tenanting/tenant_resolver.rb
return unless Campfire.saas?

Rails.application.configure do
  config.active_record_tenanted.tenant_resolver = ->(request) {
    if request.path_info =~ /\A\/(\d{7,})/
      $1
    elsif request.script_name =~ /\A\/(\d{7,})/
      $1
    end
  }
end
```

**Key Difference:**
- Fizzy: Custom middleware sets `Current.account` manually, stores ID in `env["fizzy.external_account_id"]`
- Campfire: Gem handles path rewriting automatically, stores tenant in `ApplicationRecord.current_tenant`

---

## Identity Models

### Fizzy - Identity (Same Database)
```ruby
# app/models/identity.rb
class Identity < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :auth_codes, dependent: :destroy
  has_many :users, dependent: :nullify
  has_many :accounts, through: :users

  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }
  normalizes :email_address, with: ->(value) { value.strip.downcase.presence }

  def send_auth_code(**attributes)
    auth_codes.create!(attributes).tap do |auth_code|
      AuthCodeMailer.sign_in_instructions(auth_code).deliver_later
    end
  end
end
```

### Campfire-CE - GlobalIdentity (Untenanted Database)
```ruby
# saas/app/models/global_identity.rb
class GlobalIdentity < UntenantedRecord
  has_many :global_sessions, dependent: :destroy
  has_many :auth_codes, dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy

  validates :email_address, presence: true,
                           uniqueness: { case_sensitive: false },
                           format: { with: URI::MailTo::EMAIL_REGEXP }
  normalizes :email_address, with: ->(email) { email.strip.downcase }

  def verified?
    verified_at.present?
  end

  def workspaces
    Workspace.where(external_id: workspace_memberships.pluck(:tenant).map(&:to_i))
  end
end
```

**Key Differences:**
| Aspect | Fizzy | Campfire-CE |
|--------|-------|-------------|
| Base class | `ApplicationRecord` | `UntenantedRecord` |
| Database | Same as tenanted data | Separate untenanted DB |
| User link | Direct `has_many :users` | Via `workspace_memberships` |
| Verification | Not tracked | `verified_at` timestamp |

---

## Session Models

### Fizzy
```ruby
# app/models/session.rb
class Session < ApplicationRecord
  belongs_to :identity
end
# Uses Rails' signed_id for cookie: Session.find_signed(cookies.signed[:session_token])
```

### Campfire-CE
```ruby
# saas/app/models/global_session.rb
class GlobalSession < UntenantedRecord
  belongs_to :global_identity

  has_secure_token :token

  # Uses custom token column: GlobalSession.find_by(token: cookies.signed[:global_session_token])
end
```

**Difference:** Fizzy uses Rails' built-in `signed_id`. Campfire uses a custom `token` column with `has_secure_token`.

---

## User ↔ Identity Linkage

This is a **fundamental architectural difference** driven by database strategy.

### Visual Comparison

```
FIZZY (Single MySQL Database - Direct FK):
┌─────────────────────┐         ┌─────────────────────┐
│      Identity       │         │        User         │
│─────────────────────│         │─────────────────────│
│ id (UUID)           │◄────────│ identity_id (FK)    │
│ email_address       │         │ account_id (FK)     │
│ staff               │         │ name, role          │
│                     │         │                     │
│ has_many :users     │         │ belongs_to :identity│
│ has_many :accounts, │         │ belongs_to :account │
│   through: :users   │         │                     │
└─────────────────────┘         └─────────────────────┘
        Same MySQL database - direct association works


CAMPFIRE-CE (Separate SQLite Databases - Bridge Required):
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   GlobalIdentity    │    │ WorkspaceMembership │    │        User         │
│─────────────────────│    │─────────────────────│    │─────────────────────│
│ id                  │◄───│ global_identity_id  │    │ workspace_          │
│ email_address       │    │ tenant (string)     │───►│   membership_id     │
│                     │    │ user_id (cached)    │    │ name, role          │
│                     │    │                     │    │                     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
   Untenanted DB              Untenanted DB              Per-workspace DB
                     ▲                           ▲
                     └───── Cross-DB bridge ─────┘
```

### Fizzy - Direct Association (Same Database)
```ruby
# app/models/identity.rb
class Identity < ApplicationRecord
  has_many :users, dependent: :nullify
  has_many :accounts, through: :users
end

# app/models/user.rb
class User < ApplicationRecord
  belongs_to :account
  belongs_to :identity, optional: true
end

# Schema: users table has identity_id FK
# Unique index on (account_id, identity_id) - one identity per account
```

### Campfire-CE - Via WorkspaceMembership (Cross-Database)
```ruby
# app/models/user.rb (core app, per-workspace DB)
class User < ApplicationRecord
  belongs_to :workspace_membership, optional: true, class_name: "WorkspaceMembership"

  def global_identity
    return nil unless Campfire.saas?
    workspace_membership&.global_identity
  end
end

# saas/app/models/workspace_membership.rb (untenanted DB)
class WorkspaceMembership < UntenantedRecord
  belongs_to :global_identity, touch: true

  def user
    return nil if user_id.blank?
    ApplicationRecord.with_tenant(tenant) { User.find_by(id: user_id) }
  end

  def create_user!(name: nil, role: :member)
    ApplicationRecord.with_tenant(tenant) do
      user = User.create!(
        workspace_membership_id: id,
        email_address: global_identity.email_address,
        name: name || global_identity.email_address.split("@").first,
        role: role
      )
      cache_user_id!(user.id)
      user
    end
  end
end
```

**Why the difference?**

| Aspect | Fizzy | Campfire-CE |
|--------|-------|-------------|
| Database | Single MySQL | SQLite per-workspace |
| FK possible? | Yes - same DB | No - different DB files |
| Association | Direct `has_many :users` | Via `WorkspaceMembership` bridge |
| User lookup | `identity.users.find_by(account:)` | `workspace_membership.user` (with tenant switch) |
| Cached user_id? | No - FK is enough | Yes - avoids repeated tenant switch |

---

## Current Attributes

### Fizzy
```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :identity, :account
  attribute :http_method, :request_id, :user_agent, :ip_address, :referrer

  def session=(value)
    super(value)
    self.identity = session.identity if value.present?
  end

  def identity=(identity)
    super(identity)
    self.user = identity.users.find_by(account: account) if identity.present?
  end

  def with_account(value, &)
    with(account: value, &)
  end
end
```

### Campfire-CE
```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :request
  attribute :global_session, :workspace_membership  # SaaS mode

  def session=(value)
    super
    self.user = value&.user unless Campfire.saas?
  end

  def global_session=(value)
    super
    return if value.nil?
    if Campfire.saas? && ApplicationRecord.current_tenant.present?
      self.workspace_membership = value.global_identity
        &.workspace_memberships&.find_by(tenant: ApplicationRecord.current_tenant)
    end
  end

  def user
    if Campfire.saas? && workspace_membership.present?
      workspace_membership.user
    else
      super
    end
  end

  def workspace
    return nil unless Campfire.saas? && ApplicationRecord.current_tenant.present?
    @workspace ||= Workspace.find_by(external_id: ApplicationRecord.current_tenant)
  end
end
```

**Key Difference:** Campfire has conditional `Campfire.saas?` checks to maintain single-tenant compatibility.

---

## Authentication Concern

### Fizzy
```ruby
# app/controllers/concerns/authentication.rb
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_account
    before_action :require_authentication
  end

  class_methods do
    def disallow_account_scope(**options)
      skip_before_action :require_account, **options
      before_action :redirect_tenanted_request, **options
    end
  end

  private
    def require_account
      unless Current.account.present?
        redirect_to main_app.session_menu_path(script_name: nil)
      end
    end

    def resume_session
      if session = find_session_by_cookie
        set_current_session session
      end
    end

    def find_session_by_cookie
      Session.find_signed(cookies.signed[:session_token])
    end

    def start_new_session_for(identity)
      identity.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        set_current_session session
      end
    end

    def set_current_session(session)
      Current.session = session
      cookies.signed.permanent[:session_token] = { value: session.signed_id, httponly: true, same_site: :lax }
    end
end
```

### Campfire-CE
```ruby
# saas/app/controllers/concerns/saas/authentication.rb
module Saas
  module Authentication
    extend ActiveSupport::Concern

    included do
      before_action :set_current_global_session
      helper_method :signed_in?, :current_global_identity
    end

    private
      def set_current_global_session
        if (token = cookies.signed[:global_session_token])
          Current.global_session = GlobalSession.find_by(token: token)
        end
      end

      def signed_in?
        Current.global_identity.present?
      end

      def sign_in(global_identity)
        global_session = global_identity.global_sessions.create!(
          user_agent: request.user_agent,
          ip_address: request.remote_ip
        )
        cookies.signed.permanent[:global_session_token] = {
          value: global_session.token,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax
        }
        Current.global_session = global_session
      end

      def after_authentication_url
        stored_url = session.delete(:return_to_after_authenticating)
        return stored_url if stored_url.present? && safe_redirect_url?(stored_url)
        workspaces_path
      end
  end
end
```

**Key Differences:**
| Aspect | Fizzy | Campfire-CE |
|--------|-------|-------------|
| Account check | `require_account` before_action | No account check (tenant from URL) |
| Session lookup | `Session.find_signed` | `GlobalSession.find_by(token:)` |
| Untenanted routes | `disallow_account_scope` | Route constraints |
| Cookie name | `:session_token` | `:global_session_token` |

---

## AuthCode Implementation

### Fizzy
```ruby
# app/models/auth_code.rb
class AuthCode < ApplicationRecord
  CODE_LENGTH = 6
  EXPIRATION_TIME = 15.minutes

  belongs_to :identity
  enum :purpose, %w[ sign_in sign_up ], prefix: :for

  def self.consume(code)
    active.find_by(code: Code.sanitize(code))&.consume
  end

  def consume
    destroy
    self  # Returns the auth_code
  end
end

# app/models/auth_code/code.rb
module AuthCode::Code
  def self.generate(length)
    SecureRandom.base32(length)
  end

  def self.sanitize(code)
    normalize_code(code)
      .then { apply_substitutions(it) }
      .then { remove_invalid_characters(it) }
  end
end
```

### Campfire-CE
```ruby
# saas/app/models/auth_code.rb
class AuthCode < UntenantedRecord
  CODE_LENGTH = 6
  EXPIRATION_TIME = 15.minutes

  belongs_to :global_identity
  enum :purpose, %i[sign_in sign_up], prefix: :for

  def self.consume(code)
    active.find_by(code: Code.sanitize(code))&.consume
  end

  def consume
    global_identity.tap { destroy }  # Returns the global_identity
  end
end

# saas/app/models/auth_code/code.rb
module AuthCode::Code
  CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".chars.freeze  # No O, I, L

  def self.generate(length)
    length.times.map { CODE_ALPHABET.sample }.join
  end
end
```

**Differences:**
- Fizzy `consume` returns the auth_code itself
- Campfire `consume` returns the `global_identity` directly
- Campfire uses a custom alphabet excluding ambiguous characters (O, I, L)

---

## ActionCable Connection

### Fizzy
```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        if session = find_session_by_cookie
          account = Account.find_by(external_account_id: request.env["fizzy.external_account_id"])
          Current.account = account
          self.current_user = session.identity.users.find_by!(account: account) if account
        end
      end
  end
end
```

### Campfire-CE
```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      super if Campfire.saas?  # Let gem set current_tenant
      Campfire.saas? ? connect_saas : connect_single_tenant
    end

    private
      def connect_saas
        global_session = find_session_by_cookie
        return reject_unauthorized_connection unless global_session

        ws_id = current_tenant  # From gem
        return reject_unauthorized_connection unless ws_id

        membership = global_session.global_identity.workspace_memberships.find_by(tenant: ws_id)
        return reject_unauthorized_connection unless membership

        user = ApplicationRecord.with_tenant(ws_id) { membership.user || membership.create_user! }
        self.current_user = user
      end
  end
end
```

**Key Differences:**
- Fizzy uses `env["fizzy.external_account_id"]` from middleware
- Campfire uses gem's `current_tenant` and calls `super` to initialize gem
- Campfire creates user lazily if not exists

---

## Tenanting Helper

### Fizzy
```ruby
# app/helpers/tenanting_helper.rb
module TenantingHelper
  def tenanted_action_cable_meta_tag
    tag "meta",
        name: "action-cable-url",
        content: "#{request.script_name}#{ActionCable.server.config.mount_path}"
  end
end
```

### Campfire-CE
```ruby
# saas/app/helpers/tenanting_helper.rb
module TenantingHelper
  def tenanted_action_cable_meta_tag
    tag "meta",
        name: "action-cable-url",
        content: "#{request.script_name}#{ActionCable.server.config.mount_path}"
  end

  # Generate URL without workspace prefix (for join links, etc.)
  def untenanted_url(route_name, *args)
    url_options = { script_name: "", host: request.host, port: request.port, protocol: request.protocol }
    Rails.application.routes.url_helpers.public_send(:"#{route_name}_url", *args, **url_options)
  end

  def untenanted_path(route_name, *args)
    url_options = { script_name: "" }
    Rails.application.routes.url_helpers.public_send(:"#{route_name}_path", *args, **url_options)
  end
end
```

**Difference:** Campfire adds `untenanted_url/path` helpers for generating URLs outside workspace context.

---

## Workspace Selector (MVP-7)

### Fizzy
```ruby
# app/controllers/sessions/menus_controller.rb
class Sessions::MenusController < ApplicationController
  disallow_account_scope
  layout "public"

  def show
    @accounts = Current.identity.accounts.active

    # Auto-redirect if only one workspace
    if @accounts.one?
      redirect_to root_url(script_name: @accounts.first.slug)
    end
  end
end
```

### Campfire-CE
```ruby
# saas/app/controllers/saas/workspaces_controller.rb
class Saas::WorkspacesController < BaseController
  def index
    @workspaces = current_global_identity
      .workspace_memberships
      .includes(:workspace)
      .map(&:workspace)
      .compact
      .select(&:active?)

    # Auto-redirect if user has exactly one workspace (better UX)
    if @workspaces.one?
      redirect_to "/#{@workspaces.first.external_id}"
    end
  end
end

# saas/app/helpers/workspace_selector_helper.rb
module WorkspaceSelectorHelper
  def show_workspace_selector?
    Campfire.saas? && Current.global_identity.present? &&
      Current.global_identity.workspace_memberships.count >= 1
  end

  def user_workspaces
    Current.global_identity.workspace_memberships.includes(:workspace).map do |m|
      { workspace: m.workspace, active: m.tenant == ApplicationRecord.current_tenant.to_s }
    end
  end
end
```

**Key Differences:**
| Aspect | Fizzy | Campfire-CE |
|--------|-------|-------------|
| Controller location | `Sessions::MenusController` | `Saas::WorkspacesController` |
| Layout | `public` | `saas` (outside workspace context) |
| Workspace access | `Current.identity.accounts` | Via `workspace_memberships` (cross-DB) |
| Auto-redirect | Single workspace → auto-redirect | Same pattern adopted |

---

## Registration & Profile (MVP-8)

### Fizzy
```ruby
# Registration happens via SessionsController, not a separate controller
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  disallow_account_scope
  require_unauthenticated_access except: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create

  def create
    if identity = Identity.find_by(email_address: email_address)
      redirect_to_session_auth_code identity.send_auth_code
    elsif Account.accepting_signups?
      signup = Signup.new(email_address: email_address)
      if signup.valid?(:identity_creation)
        auth_code = signup.create_identity
        redirect_to_session_auth_code auth_code
      end
    end
  end
end

# app/models/signup.rb - ActiveModel::Model, not ApplicationRecord
class Signup
  include ActiveModel::Model
  include ActiveModel::Attributes

  attr_accessor :email_address, :identity

  def create_identity
    @identity = Identity.find_or_create_by!(email_address: email_address)
    @identity.send_auth_code for: :sign_up
  end

  def complete
    # Creates account with billing via Queenbee
    create_account
  end
end
```

### Campfire-CE
```ruby
# saas/app/controllers/saas/registrations_controller.rb
class Saas::RegistrationsController < BaseController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create

  def create
    global_identity = GlobalIdentity.find_or_create_by!(email_address: params[:email_address])
    auth_code = global_identity.auth_codes.create!(purpose: :sign_up)
    AuthCodeMailer.code(auth_code).deliver_later
    redirect_to auth_code_path
  end
end

# saas/app/controllers/saas/profiles_controller.rb
class Saas::ProfilesController < BaseController
  def update
    if current_global_identity.update(profile_params)
      # Email change requires re-verification
      if current_global_identity.saved_change_to_email_address?
        current_global_identity.update!(verified_at: nil)
        sign_out
        redirect_to new_session_path, notice: "Please verify your new email"
      else
        redirect_to workspaces_path
      end
    end
  end
end
```

**Key Differences:**
| Aspect | Fizzy | Campfire-CE |
|--------|-------|-------------|
| Registration location | Via `SessionsController` | Separate `RegistrationsController` |
| Signup model | `ActiveModel::Model` with validation contexts | Direct `GlobalIdentity.find_or_create_by!` |
| Signup gating | `Account.accepting_signups?` check | Open signup (billing deferred to v2) |
| Email change | Via User model | Via `GlobalIdentity` with re-verification |
| Rate limiting | Rails 8 `rate_limit` | Same pattern |

---

## Workspace Management (MVP-9)

### Fizzy
```ruby
# Account creation via Signup.complete (billing-gated)
# app/models/account.rb
class Account < ApplicationRecord
  def self.create_with_owner(account:, owner:)
    create!(**account).tap do |account|
      account.users.create!(role: :system, name: "System")
      account.users.create!(**owner.with_defaults(role: :owner, verified_at: Time.current))
    end
  end
end

# Join codes: app/controllers/join_codes_controller.rb
class JoinCodesController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create

  before_action :set_join_code

  def create
    @join_code.redeem_if { |account| @identity.join(account) }
    user = User.active.find_by!(account: @join_code.account, identity: @identity)

    if @identity == Current.identity && user.setup?
      redirect_to landing_url(script_name: @join_code.account.slug)
    else
      redirect_to_session_auth_code @identity.send_auth_code,
        return_to: new_users_verification_url(script_name: @join_code.account.slug)
    end
  end
end

# app/models/identity/joinable.rb
module Identity::Joinable
  def join(account, **attributes)
    attributes[:name] ||= email_address
    transaction do
      account.users.find_or_create_by!(identity: self) do |user|
        user.assign_attributes(attributes)
      end
    end
  end
end
```

### Campfire-CE
```ruby
# saas/app/controllers/saas/workspaces_controller.rb
class Saas::WorkspacesController < BaseController
  allow_unauthenticated_access only: :join

  def create
    workspace = Workspace.create_with_database!(
      name: params[:name],
      creator: current_global_identity
    )
    redirect_to "/#{workspace.external_id}"
  end

  def join
    @workspace = Workspace.find_by_join_code(params[:code])
    return render status: :not_found unless @workspace

    return if request.get?  # Show join page
    return redirect_to new_session_path unless current_global_identity

    current_global_identity.workspace_memberships.find_or_create_by!(tenant: @workspace.external_id.to_s)
    redirect_to "/#{@workspace.external_id}"
  end
end

# saas/app/models/workspace.rb
class Workspace < UntenantedRecord
  def self.create_with_database!(name:, creator:, slug: nil)
    transaction do
      workspace = create!(name: name, slug: slug, creator: creator)
      ApplicationRecord.create_tenant(workspace.external_id.to_s)

      # Create initial workspace data
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        Account.create!(name: name)
        # Create owner user, default rooms, etc.
      end

      workspace
    end
  end

  def self.find_by_join_code(code)
    find_each do |workspace|
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        return workspace if Account.first&.join_codes&.active&.exists?(code: code)
      end
    end
    nil
  end
end
```

**Key Differences:**
| Aspect | Fizzy | Campfire-CE |
|--------|-------|-------------|
| Workspace creation | Via `Signup.complete` (billing-gated) | User self-service via `Workspace.create_with_database!` |
| Join codes | `JoinCodesController` with `identity.join(account)` | `WorkspacesController#join` with membership creation |
| User creation on join | `account.users.find_or_create_by!(identity:)` | Via `WorkspaceMembership.create_user!` (lazy) |
| Database creation | N/A (single MySQL DB) | `ApplicationRecord.create_tenant` (new SQLite file) |
| Initial data | Account + system user + owner | Account + owner User + default rooms |

---

## Summary: When to Use Each Pattern

### Use Fizzy's Pattern When:
- Single database with logical tenant separation
- All data in one MySQL instance
- Simpler cross-tenant queries needed
- Billing/subscription built-in required

### Use Campfire's Pattern When:
- Physical database isolation required (compliance, security)
- SQLite per-tenant for self-hosting simplicity
- Need to maintain single-tenant compatibility
- Smaller deployments where separate DBs are manageable

---

## Patterns Adopted from Fizzy

1. **Path-based tenanting** with 7+ digit IDs
2. **Identity + User separation** (GlobalIdentity + per-workspace User)
3. **AuthCode OTP** flow with code sanitization
4. **`tenanted_action_cable_meta_tag`** helper
5. **`CurrentRequest` concern** for request metadata
6. **`script_name` manipulation** for URL generation
7. **SaaS folder as Rails engine** pattern
8. **Single-workspace auto-redirect** - skip workspace selector if user has exactly one workspace

## Patterns from Fizzy Plan B (MySQL Migration) - Reviewed

Fizzy's "Plan B" (PR #1558) migrated from SQLite+`activerecord-tenanted` to MySQL. We reviewed these patterns:

| Pattern | Adopted? | Notes |
|---------|----------|-------|
| `Current.with_account` / `without_account` | No | We use `ApplicationRecord.with_tenant` from gem instead |
| `disallow_account_scope` DSL | No | Achieved via `Saas::BaseController` inheriting from `ActionController::Base` |
| Single-workspace auto-redirect | **Yes** | Implemented in `WorkspacesController#index` |
| UUID primary keys | No | MySQL-specific, not needed for SQLite |
| Database read replicas | No | MySQL-specific scaling pattern |
| Direct `User.belongs_to :identity` | No | We need `WorkspaceMembership` bridge for cross-DB linking |

## Patterns Unique to Campfire-CE

1. **`activerecord-tenanted` gem** for automatic scoping
2. **`UntenantedRecord` base class** for global models
3. **`WorkspaceMembership` bridge** for cross-DB linking
4. **Lazy user creation** on first workspace visit
5. **`untenanted_url/path` helpers** for join links
6. **Conditional `Campfire.saas?`** checks for compatibility
