require "test_helper"

class User::Bot::WebhookSignerTest < ActiveSupport::TestCase
  setup do
    @bot = users(:bender)
    @bot.update!(webhook_secret: "whsec_abcdef1234567890")
  end

  test "headers include all four X-Sabha-* fields" do
    headers = User::Bot::WebhookSigner.headers_for(bot: @bot, event_name: "message_created", raw_body: %({"hello":"world"}))

    assert headers["X-Sabha-Signature"].start_with?("sha256=")
    assert_match(/\A\d+\z/, headers["X-Sabha-Timestamp"])
    assert_equal "message_created", headers["X-Sabha-Event"]
    assert_match(/\A[0-9a-f-]{36}\z/, headers["X-Sabha-Delivery"])
  end

  test "signature is HMAC-SHA256 over timestamp.raw_body" do
    frozen_time = Time.utc(2026, 4, 24, 12, 0, 0)

    travel_to(frozen_time) do
      raw_body = %({"event":"message_created"})
      headers = User::Bot::WebhookSigner.headers_for(bot: @bot, event_name: "message_created", raw_body: raw_body)

      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", @bot.webhook_secret, "#{headers['X-Sabha-Timestamp']}.#{raw_body}")
      assert_equal expected, headers["X-Sabha-Signature"]
    end
  end

  test "each delivery gets a unique X-Sabha-Delivery uuid" do
    a = User::Bot::WebhookSigner.headers_for(bot: @bot, event_name: "x", raw_body: "")
    b = User::Bot::WebhookSigner.headers_for(bot: @bot, event_name: "x", raw_body: "")

    assert_not_equal a["X-Sabha-Delivery"], b["X-Sabha-Delivery"]
  end

  test "lazy-generates webhook_secret when blank" do
    @bot.update!(webhook_secret: nil)

    User::Bot::WebhookSigner.headers_for(bot: @bot, event_name: "message_created", raw_body: "{}")

    assert @bot.reload.webhook_secret.present?
    assert_match(/\Awhsec_/, @bot.webhook_secret)
  end
end
