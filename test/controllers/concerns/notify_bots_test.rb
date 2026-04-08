require "test_helper"

class NotifyBotsTest < ActionDispatch::IntegrationTest
  include MentionTestHelper

  setup do
    @room = rooms(:watercooler)
    @bot = users(:bender)
    sign_in :david
    WebMock.stub_request(:post, webhooks(:bender).url).to_return(status: 200)
    WebMock.stub_request(:post, webhooks(:nsa).url).to_return(status: 200)
    WebMock.stub_request(:post, webhooks(:betty).url).to_return(status: 200)
  end

  # message_created

  test "mentioning a bot broadcasts to its WebSocket channel" do
    stream = "bot_events:#{@bot.id}"

    assert_broadcasts stream, 1 do
      post room_messages_url(@room, format: :turbo_stream), params: { message: {
        body: "<div>Hey #{mention_attachment_for(:bender)}</div>", client_message_id: SecureRandom.uuid } }
    end
  end

  test "mentioning a bot also enqueues webhook delivery" do
    assert_enqueued_jobs 1, only: Bot::WebhookJob do
      post room_messages_url(@room, format: :turbo_stream), params: { message: {
        body: "<div>Hey #{mention_attachment_for(:bender)}</div>", client_message_id: SecureRandom.uuid } }
    end
  end

  test "bot without webhook still receives WebSocket broadcast" do
    @bot.webhook.destroy!
    @bot.reload

    stream = "bot_events:#{@bot.id}"

    assert_broadcasts stream, 1 do
      assert_no_enqueued_jobs only: Bot::WebhookJob do
        post room_messages_url(@room, format: :turbo_stream), params: { message: {
          body: "<div>Hey #{mention_attachment_for(:bender)}</div>", client_message_id: SecureRandom.uuid } }
      end
    end
  end

  test "non-mentioned bot does not receive broadcast in non-direct room" do
    stream = "bot_events:#{@bot.id}"

    assert_no_broadcasts stream do
      post room_messages_url(@room, format: :turbo_stream), params: { message: {
        body: "<div>Hello world</div>", client_message_id: SecureRandom.uuid } }
    end
  end

  test "multiple mentioned bots each receive their own broadcast" do
    bender_stream = "bot_events:#{users(:bender).id}"
    nsa_stream = "bot_events:#{users(:nsa).id}"

    assert_broadcasts bender_stream, 1 do
      assert_broadcasts nsa_stream, 1 do
        post room_messages_url(@room, format: :turbo_stream), params: { message: {
          body: "<div>Hey #{mention_attachment_for(:bender)} and #{mention_attachment_for(:nsa)}</div>",
          client_message_id: SecureRandom.uuid } }
      end
    end
  end

  # message_updated

  test "message update broadcasts to eligible bots" do
    message = messages(:sixth) # david's message in watercooler
    stream = "bot_events:#{@bot.id}"

    assert_broadcasts stream, 1 do
      put room_message_url(@room, message), params: { message: { body: "Updated body" } }
    end
  end

  # message_deleted

  test "message delete broadcasts to eligible bots" do
    message = messages(:sixth)
    stream = "bot_events:#{@bot.id}"

    assert_broadcasts stream, 1 do
      delete room_message_url(@room, message, format: :turbo_stream)
    end
  end

  # boost events

  test "boost created broadcasts to eligible bots" do
    message = messages(:sixth)
    stream = "bot_events:#{@bot.id}"

    assert_broadcasts stream, 1 do
      post message_boosts_url(message, format: :turbo_stream), params: { boost: { content: "Nice!" } }
    end
  end

  test "boost deleted broadcasts to eligible bots" do
    message = messages(:sixth)
    boost = message.boosts.create!(content: "Nice!", booster: users(:david))
    stream = "bot_events:#{@bot.id}"

    assert_broadcasts stream, 1 do
      delete message_boost_url(message, boost, format: :turbo_stream)
    end
  end

  # user events (account-level, no room — else branch)

  test "user deletion broadcasts to all active bots" do
    sign_in :david # david is admin
    kevin = users(:kevin)
    bender_stream = "bot_events:#{users(:bender).id}"

    assert_broadcasts bender_stream, 1 do
      delete account_user_url(kevin, format: :turbo_stream)
    end
  end
end
