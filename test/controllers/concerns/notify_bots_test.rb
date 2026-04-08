require "test_helper"

class NotifyBotsTest < ActionDispatch::IntegrationTest
  include MentionTestHelper

  setup do
    @room = rooms(:watercooler)
    @bot = users(:bender)
    sign_in :david
    WebMock.stub_request(:post, webhooks(:bender).url).to_return(status: 200)
    WebMock.stub_request(:post, webhooks(:nsa).url).to_return(status: 200)
  end

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
    # bender has involvement: mentions in watercooler — no mention means no broadcast
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
end
