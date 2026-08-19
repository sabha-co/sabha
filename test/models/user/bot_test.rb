require "test_helper"

class User::BotTest < ActiveSupport::TestCase
  test "create bot mints a shown-once sabha key" do
    bot = User.create_bot!(name: "Bender")

    assert_match(/\Asabha_bot_[0-9a-f]{32}\z/, bot.plaintext_bot_key)
    assert_equal bot.plaintext_bot_key, bot.bot_key
    assert_equal bot, User.authenticate_bot(bot.bot_key)
    assert_nil User.find(bot.id).bot_key, "the key is not recoverable after the mint window"
  end

  test "create_bot! always generates webhook_secret even without webhook_url" do
    bot = User.create_bot!(name: "NoWebhook")
    assert_nil bot.webhook_url
    assert_match(/\Awhsec_/, bot.webhook_secret)
  end

  test "create_bot! generates webhook_secret when webhook_url is present" do
    bot = User.create_bot!(name: "WithWebhook", webhook_url: "https://example.com/hook")
    assert_equal "https://example.com/hook", bot.webhook_url
    assert_match(/\Awhsec_/, bot.webhook_secret)
  end

  test "reset bot key mints a new key and retires the old one" do
    bot = User.create_bot!(name: "Bender")
    old_key = bot.bot_key

    bot.reset_bot_key
    new_key = bot.bot_key

    assert_not_equal old_key, new_key
    assert_match(/\Asabha_bot_/, new_key)
    assert_equal bot, User.authenticate_bot(new_key)
    assert_nil User.authenticate_bot(old_key), "the previous key stops working immediately"
  end

  test "authenticate" do
    bot = User.create_bot!(name: "Bender")
    assert User.authenticate_bot(bot.bot_key)
  end

  test "authenticate accepts a legacy id-token key from before the digest cutover" do
    # Fixture bots carry a bot_token and no digest, standing in for bots minted
    # before the cutover; their derivable "<id>-<token>" key must still work.
    bot = users(:bender)
    assert bot.bot_token.present?
    assert_nil bot.bot_key_digest
    assert_equal bot, User.authenticate_bot(bot.bot_key)
  end

  test "authenticate fails with empty token" do
    bot = User.create_bot!(name: "Bender")
    malformed_key = "#{bot.id}-"
    assert_nil User.authenticate_bot(malformed_key)
  end

  test "authenticate does not impersonate regular users" do
    regular_user = users(:david)
    assert_not regular_user.bot?

    # Try to authenticate as regular user using their ID with nil token
    malformed_key = "#{regular_user.id}-"
    assert_nil User.authenticate_bot(malformed_key), "Should not authenticate regular user via bot authentication"
  end

  test "authenticate fails with incorrect token" do
    bot = User.create_bot!(name: "Bender")
    wrong_key = "#{bot.id}-wrongtoken"
    assert_nil User.authenticate_bot(wrong_key)
  end

  test "deliver message by webhook" do
    WebMock.stub_request(:post, webhooks(:bender).url).to_return(status: 200)

    perform_enqueued_jobs only: Bot::WebhookJob do
      users(:bender).deliver_webhook_later(messages(:first), :created)
    end
  end
end
