require "test_helper"

class WebhookTest < ActiveSupport::TestCase
  test "payload contains absolute URLs" do
    message = messages(:first)
    base_url = "https://sabha.test"
    message_url = base_url + Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
    messages_url = base_url + Rails.application.routes.url_helpers.api_bots_room_messages_path(message.room)
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

  test "delivery with reply posts size-limit message when body exceeds cap" do
    oversize = "x" * (Webhook::MAX_REPLY_BODY_SIZE + 1)
    WebMock.stub_request(:post, webhooks(:betty).url).to_return(status: 200, body: oversize, headers: { "Content-Type" => "text/plain" })

    webhooks(:betty).deliver_now(messages(:first), :created, reply: true)

    reply_message = Message.last
    assert_equal "Bot reply exceeded #{Webhook::MAX_REPLY_BODY_SIZE / 1.megabyte}MB limit", reply_message.body.to_plain_text
  end

  test "size cap fires before attachment blob is created for oversize image reply" do
    oversize_image = "x" * (Webhook::MAX_REPLY_BODY_SIZE + 1)
    WebMock.stub_request(:post, webhooks(:betty).url).to_return(status: 200, body: oversize_image, headers: { "Content-Type" => "image/png" })

    assert_no_difference -> { ActiveStorage::Blob.count } do
      webhooks(:betty).deliver_now(messages(:first), :created, reply: true)
    end

    reply_message = Message.last
    assert_equal "Bot reply exceeded #{Webhook::MAX_REPLY_BODY_SIZE / 1.megabyte}MB limit", reply_message.body.to_plain_text
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

  test "outbound POST carries HMAC signature headers" do
    webhook = webhooks(:betty)
    webhook.user.update!(webhook_secret: "whsec_testsecret12345")

    WebMock.stub_request(:post, webhook.url).to_return(status: 200, body: "", headers: {})

    webhook.deliver_now(messages(:first), :created)

    assert_requested :post, webhook.url do |request|
      request.headers["X-Sabha-Signature"].to_s.start_with?("sha256=") &&
        request.headers["X-Sabha-Timestamp"].to_s.match?(/\A\d+\z/) &&
        request.headers["X-Sabha-Event"] == "message_created" &&
        request.headers["X-Sabha-Delivery"].to_s.match?(/\A[0-9a-f-]{36}\z/)
    end
  end

  test "url validation rejects malformed URLs" do
    webhook = Webhook.new(user: users(:david), url: "not a url")
    assert_not webhook.valid?
    assert_includes webhook.errors[:url], "must be a valid HTTP(S) URL"
  end

  test "url validation distinguishes DNS failure from private addresses" do
    stub_dns_resolution
    unresolvable = Webhook.new(user: users(:david), url: "https://nowhere.example.com/hook")
    assert_not unresolvable.valid?
    assert_includes unresolvable.errors[:url], "could not be resolved"

    stub_dns_resolution("192.168.1.1")
    private_target = Webhook.new(user: users(:david), url: "https://internal.example.com/hook")
    assert_not private_target.valid?
    assert_includes private_target.errors[:url], "must not target private or internal networks"

    stub_dns_resolution("93.184.216.34")
    public_target = Webhook.new(user: users(:david), url: "https://example.com/hook")
    assert public_target.valid?, public_target.errors.full_messages.to_sentence
  end
end
