ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

require "rails/test_help"
require "minitest/unit"
require "mocha/minitest"
require "webmock/minitest"

# Require test helpers
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/mention_test_helper"
require_relative "test_helpers/turbo_test_helper"

WebMock.enable!

class ActiveSupport::TestCase
  # FIXME: Why isn't this included in ActiveSupport::TestCase by default?
  include ActiveJob::TestHelper

  # parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  include SessionTestHelper, MentionTestHelper, TurboTestHelper

  setup do
    ActionCable.server.pubsub.clear

    Rails.configuration.tap do |config|
      config.x.web_push_pool.shutdown
      config.x.web_push_pool = WebPush::Pool.new \
        invalid_subscription_handler: config.x.web_push_pool.invalid_subscription_handler
    end

    # Set ENV vars for tests
    # Don't set COOKIE_DOMAIN in tests to allow cookies to work across different test hosts
    ENV["COOKIE_DOMAIN"] = nil

    WebMock.disable_net_connect!
  end

  teardown do
    WebMock.reset!
  end
end
