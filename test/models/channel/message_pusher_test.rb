require "test_helper"

class Channel::MessagePusherTest < ActiveSupport::TestCase
  test "build_payload for shared channels uses channel display_name as title and creator-prefixed body" do
    message = channels(:designers).messages.create!(
      body: "Shared channel update",
      creator: users(:david),
      client_message_id: "pusher_shared_payload"
    )

    payload = Channel::MessagePusher.payload_for(channel: message.channel, message: message)

    assert_equal channels(:designers).display_name, payload[:title]
    assert_equal "David: Shared channel update", payload[:body]
    assert_equal Rails.application.routes.url_helpers.channel_path(channels(:designers)), payload[:path]
  end

  test "build_payload for direct channels uses sender name as title and unprefixed body" do
    message = channels(:david_and_jason).messages.create!(
      body: "Direct payload",
      creator: users(:jason),
      client_message_id: "pusher_direct_payload"
    )

    payload = Channel::MessagePusher.payload_for(channel: message.channel, message: message)

    assert_equal "Jason", payload[:title]
    assert_equal "Direct payload", payload[:body]
    assert_equal Rails.application.routes.url_helpers.channel_path(channels(:david_and_jason)), payload[:path]
  end

  test "build_payload for thread replies points back to the parent message" do
    parent = channels(:pets).messages.create!(
      body: "Pusher thread parent",
      creator: users(:david),
      client_message_id: "pusher_thread_parent"
    )
    thread = Channels::Thread.create!(parent_message: parent, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason) ])
    reply = thread.messages.create!(
      body: "Pusher thread reply",
      creator: users(:jason),
      client_message_id: "pusher_thread_reply"
    )

    payload = Channel::MessagePusher.payload_for(channel: thread, message: reply)

    expected_path = Rails.application.routes.url_helpers.channel_at_message_path(parent.channel, parent)
    assert_equal expected_path, payload[:path]
  end

  test "build_payload for a forum post reply deep-links to the reply" do
    post = Current.set(user: users(:david)) { channels(:help_desk).post!(title: "Deploys", body: "How?") }
    reply = post.messages.create!(body: "Like this", creator: users(:david), client_message_id: "pusher_post_reply")

    payload = Channel::MessagePusher.payload_for(channel: post, message: reply)

    expected_path = Rails.application.routes.url_helpers.channel_path(post.parent_channel, post: post.slug, message_id: reply.id)
    assert_equal expected_path, payload[:path]
  end

  test "build_payload for a forum post opening message links to the gallery deep-link with no reply anchor" do
    post = Current.set(user: users(:david)) { channels(:help_desk).post!(title: "Deploys", body: "How?") }
    opening = post.messages.first

    payload = Channel::MessagePusher.payload_for(channel: post, message: opening)

    assert_equal Rails.application.routes.url_helpers.channel_path(post.parent_channel, post: post.slug), payload[:path]
  end
end
