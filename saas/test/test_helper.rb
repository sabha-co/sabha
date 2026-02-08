# frozen_string_literal: true

# SaaS Test Helper
#
# IMPORTANT: SaaS tests must be run with the SAAS environment variable set:
#   SAAS=true bin/rails test saas/test/
#
# The environment variable must be set BEFORE Rails loads so the tenanted
# gem initializes correctly. Setting it in this file is too late.

ENV["RAILS_ENV"] ||= "test"
ENV["SAAS"] ||= "true" # Reminder only - must also be set when invoking Rails

require_relative "../../config/environment"
require "rails/test_help"
require "mocha/minitest"
require "webmock/minitest"

require_relative "../../test/test_helpers/turnstile_test_helper"

# Load untenanted fixtures from saas/test/fixtures/
SAAS_FIXTURE_PATH = File.expand_path("fixtures", __dir__)

module SaasTestHelper
  extend ActiveSupport::Concern

  included do
    # Load untenanted fixtures
    self.fixture_paths = [ SAAS_FIXTURE_PATH ]
    fixtures :global_identities, :global_sessions, :workspaces, :workspace_memberships, :auth_codes
  end

  def parsed_cookies
    ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
  end

  def sign_in_global_identity(identity)
    # Create a GlobalSession for the identity
    global_session = identity.global_sessions.create!(
      user_agent: "Test Agent",
      ip_address: "127.0.0.1"
    )

    set_global_session_cookie(global_session.token)
    global_session
  end

  def sign_in_with_session(session)
    set_global_session_cookie(session.token)
  end

  def set_global_session_cookie(token)
    # In integration tests, we need to sign the cookie manually
    # This matches how the application signs cookies
    secret = Rails.application.secret_key_base
    key_generator = ActiveSupport::KeyGenerator.new(secret, iterations: 1000)
    signed_cookie_salt = Rails.application.config.action_dispatch.signed_cookie_salt || "signed cookie"
    key = key_generator.generate_key(signed_cookie_salt)
    verifier = ActiveSupport::MessageVerifier.new(key, serializer: ActiveSupport::MessageEncryptor::NullSerializer)
    signed_value = verifier.generate(token.to_json)
    cookies[:global_session_token] = signed_value
  end

  # Helper to access fixtures
  def global_identities(name)
    GlobalIdentity.find(ActiveRecord::FixtureSet.identify(name))
  end

  def global_sessions(name)
    GlobalSession.find(ActiveRecord::FixtureSet.identify(name))
  end

  def workspaces(name)
    Workspace.find(ActiveRecord::FixtureSet.identify(name))
  end

  def workspace_memberships(name)
    WorkspaceMembership.find(ActiveRecord::FixtureSet.identify(name))
  end

  def auth_codes(name)
    AuthCode.find(ActiveRecord::FixtureSet.identify(name))
  end
end

class ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SaasTestHelper

  setup do
    ActionCable.server.pubsub.clear if defined?(ActionCable.server.pubsub)
    ActionController::Base.send(:cache_store).clear
    WebMock.disable_net_connect!(allow: "localhost:8080")
  end

  teardown do
    WebMock.reset!
    Current.reset
  end
end

class ActionDispatch::IntegrationTest
  include SaasTestHelper

  # Use a valid host for SaaS tests
  setup do
    host! "www.example.com"
  end

  # Helper to make requests with workspace context
  def workspace_get(path, workspace:, **options)
    get "/#{workspace.external_id}#{path}", **options
  end

  def workspace_post(path, workspace:, **options)
    post "/#{workspace.external_id}#{path}", **options
  end

  def workspace_patch(path, workspace:, **options)
    patch "/#{workspace.external_id}#{path}", **options
  end

  def workspace_delete(path, workspace:, **options)
    delete "/#{workspace.external_id}#{path}", **options
  end
end

# ActionCable test support for SaaS mode
class ActionCable::Connection::TestCase
  include SaasTestHelper
end

class ActionCable::Channel::TestCase
  include SaasTestHelper

  # Helper to ensure tenant database exists and run block within tenant context
  def with_tenant_database(workspace)
    tenant_id = workspace.external_id.to_s

    # Create tenant database if it doesn't exist
    unless ApplicationRecord.tenant_exist?(tenant_id)
      ApplicationRecord.create_tenant(tenant_id)
    end

    ApplicationRecord.with_tenant(tenant_id) do
      yield
    end
  end
end
