require "test_helper"

class WebhookTest < ActiveSupport::TestCase
  test "payload contains absolute URLs" do
    message = messages(:first)
    base_url = "https://sabha.test"
    message_url = base_url + Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
    messages_url = base_url + Rails.application.routes.url_helpers.room_bot_messages_path(message.room, users(:bender).bot_key)
    user_url = base_url + Rails.application.routes.url_helpers.user_path(message.creator)

    WebMock.stub_request(:post, webhooks(:bender).url).
      with(
        body: hash_including(
        user: { id: message.creator.id, name: message.creator.name, role: message.creator.role, url: user_url },
        room: { id: message.room.id, name: message.room.name, type: "Closed", members: 4, has_bot: false, messages_url: messages_url },
        message: hash_including(id: message.id, body: { html: "First post!", plain: "First post!" }, has_attachment: false, attachment: nil, mentionees: [], url: message_url, thread: nil),
      ))

    response = webhooks(:bender).deliver_now(messages(:first), :created, base_url: base_url)
    assert_equal 200, response.code.to_i
  end

  test "delivery without reply" do
    WebMock.stub_request(:post, webhooks(:betty).url).to_return(status: 200, body: "", headers: {})
    response = webhooks(:betty).deliver_now(messages(:first), :created)
    assert_equal 200, response.code.to_i
  end

  test "delivery with reply posts text response" do
    WebMock.stub_request(:post, webhooks(:betty).url).to_return(status: 200, body: "Hello back!", headers: { "Content-Type" => "text/plain" })
    response = webhooks(:betty).deliver_now(messages(:first), :created, reply: true)

    reply_message = Message.last
    assert_equal "Hello back!", reply_message.body.to_plain_text
  end

  test "delivery with reply posts attachment response" do
    WebMock.stub_request(:post, webhooks(:betty).url).to_return(status: 200, body: file_fixture("moon.jpg"), headers: { "Content-Type" => "image/jpeg" })
    response = webhooks(:betty).deliver_now(messages(:first), :created, reply: true)

    reply_message = Message.last
    assert reply_message.attachment.present?
  end

  test "delivery with reply does not post on error" do
    assert_no_difference -> { Message.count } do
      WebMock.stub_request(:post, webhooks(:betty).url).to_return(status: 500, body: "Internal Error!", headers: {})
      response = webhooks(:betty).deliver_now(messages(:first), :created, reply: true)
    end
  end

  test "delivery with reply posts timeout message" do
    Webhook.any_instance.stubs(:post).raises(Net::OpenTimeout)
    response = webhooks(:betty).deliver_now(messages(:first), :created, reply: true)

    reply_message = Message.last
    assert_equal "Failed to respond within 300 seconds", reply_message.body.to_plain_text
  end

  test "delivery without reply ignores response body" do
    assert_difference -> { Message.count }, 0 do
      WebMock.stub_request(:post, webhooks(:nsa).url).to_return(status: 200, body: "Accidental text in response", headers: { "Content-Type" => "text/plain" })
      response = webhooks(:nsa).deliver_now(messages(:first), :deleted)
      assert_equal 200, response.code.to_i
    end
  end
end
