ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

require "rails/test_help"
require "minitest/unit"
require "mocha/minitest"
require "webmock/minitest"

WebMock.enable!

class ActiveSupport::TestCase
  # FIXME: Why isn't this included in ActiveSupport::TestCase by default?
  include ActiveJob::TestHelper, Turbo::Broadcastable::TestHelper

  # FIXME: sqlite3 isn't correctly creating the additional databases per core
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
    ENV["AUTH_METHOD"] = "password"
    ENV["COOKIE_DOMAIN"] = "example.com"  # Match test domain

    WebMock.disable_net_connect!
  end

  teardown do
    WebMock.reset!
  end
end
