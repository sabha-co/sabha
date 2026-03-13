ENV["RAILS_ENV"] ||= "test"
# Clear COOKIE_DOMAIN before boot so session store isn't scoped to a production domain
ENV.delete("COOKIE_DOMAIN")
require_relative "../config/environment"

require "rails/test_help"
require "mocha/minitest"
require "webmock/minitest"

# Require test helpers
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/mention_test_helper"
require_relative "test_helpers/turbo_test_helper"
require_relative "test_helpers/turnstile_test_helper"
require_relative "test_helpers/dns_test_helper"

WebMock.enable!

class ActiveSupport::TestCase
  # FIXME: Why isn't this included in ActiveSupport::TestCase by default?
  include ActiveJob::TestHelper

  # parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  include SessionTestHelper, MentionTestHelper, TurboTestHelper, DnsTestHelper

  setup do
    # Default to password auth in tests (sign_in helper uses password)
    ENV["AUTH_METHOD"] = "password"

    ActionCable.server.pubsub.clear
    ActionController::Base.send(:cache_store).clear  # Clear rate limit store

    Rails.configuration.tap do |config|
      config.x.web_push_pool.shutdown
      config.x.web_push_pool = WebPush::Pool.new \
        invalid_subscription_handler: config.x.web_push_pool.invalid_subscription_handler
    end

    # Allow localhost:8080 for AnyCable HTTP broadcasts (background threads may persist across tests)
    WebMock.disable_net_connect!(allow: "localhost:8080")
  end

  teardown do
    WebMock.reset!
    Current.reset
  end
end
