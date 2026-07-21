ENV["RAILS_ENV"] ||= "test"
# Clear COOKIE_DOMAIN before boot so session store isn't scoped to a production domain
ENV.delete("COOKIE_DOMAIN")
require_relative "../config/environment"

require "rails/test_help"

# maintain_test_schema! (triggered by requiring rails/test_help) reloads
# db/schema.rb via load_schema, not the db:prepare task, so it never runs the
# search-index ensure step and — since the search DDL is intentionally absent
# from schema.rb — leaves the test database without a search index. Provision it
# here so searchable tests have a working index on either adapter.
Message::SearchIndex.ensure!

require "mocha/minitest"
require "webmock/minitest"
if ENV["EVENT_PROF"]
  require "minitest/test_prof_plugin"
  Minitest.extensions << "test_prof"
end

# Require test helpers
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/mention_test_helper"
require_relative "test_helpers/turbo_test_helper"
require_relative "test_helpers/turnstile_test_helper"
require_relative "test_helpers/dns_test_helper"
require_relative "test_helpers/bot_api_test_helper"
require_relative "test_helpers/web_push_pool_reset"
require_relative "test_helpers/forum_test_helper"
require_relative "test_helpers/unread_test_helper"
require_relative "test_helpers/presence_test_helper"

WebMock.enable!

class ActiveSupport::TestCase
  # FIXME: Why isn't this included in ActiveSupport::TestCase by default?
  include ActiveJob::TestHelper

  # If re-enabling parallel testing, provision the search index per worker too:
  # each worker gets its own database via load_schema (which omits the
  # engine-specific search DDL), so add `parallelize_setup { Message::SearchIndex.ensure! }`
  # alongside the top-of-file ensure! call.
  # parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  include SessionTestHelper, MentionTestHelper, TurboTestHelper, DnsTestHelper, BotApiTestHelper, ForumTestHelper, UnreadTestHelper, PresenceTestHelper

  setup do
    # Default to password auth in tests (sign_in helper uses password)
    ENV["AUTH_METHOD"] = "password"

    ActionCable.server.pubsub.clear
    ActionController::Base.send(:cache_store).clear  # Clear rate limit store

    # Tests that don't explicitly stub WebPush.payload_send would otherwise make
    # real HTTP calls to fcm.googleapis.com from the web_push_pool's worker
    # thread. WebMock blocks the call but the resulting error path can race
    # with the next test's transaction rollback and destroy push subscriptions
    # outside the test's transaction (via invalid_subscription_handler). Default
    # to a no-op; tests that care use `WebPush.expects(:payload_send)` to override.
    WebPush.stubs(:payload_send).returns(nil)

    # Allow localhost:8080 for AnyCable HTTP broadcasts (background threads may persist across tests)
    WebMock.disable_net_connect!(allow: "localhost:8080")
  end

  teardown do
    WebMock.reset!
    Current.reset
  end
end
