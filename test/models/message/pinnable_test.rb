require "test_helper"
require "rails/dom/testing/assertions"

class Message::PinnableTest < ActiveSupport::TestCase
  include ActionCable::TestHelper, Rails::Dom::Testing::Assertions::SelectorAssertions

  setup do
    @room = rooms(:designers)
    @message = messages(:first)
    Current.user = users(:david)
  end

  test "pinning sets the room's single pinned message" do
    @message.pin!

    assert_equal @message, @room.reload.pinned_message
    assert @message.reload.pinned?
  end

  test "pinning replaces whatever was pinned" do
    @message.pin!
    other = messages(:second)
    other.pin!

    assert_equal other, @room.reload.pinned_message
    assert other.reload.pinned?
    assert_not @message.reload.pinned?
  end

  test "re-pinning the same message does not re-broadcast" do
    @message.pin!
    ActionCable.server.pubsub.clear

    @message.pin!

    assert_empty ActionCable.server.pubsub.broadcasts("#{@room.to_gid_param}:messages")
  end

  test "unpinning clears the room's pin" do
    @message.pin!

    @message.unpin!

    assert_nil @room.reload.pinned_message
    assert_not @message.reload.pinned?
  end

  test "soft-deleting a pinned message clears the pin" do
    @message.pin!

    @message.deactivate

    assert_nil @room.reload.pinned_message
  end

  test "destroying a pinned message nullifies the room pin" do
    @message.pin!

    @message.destroy

    assert_nil @room.reload.pinned_message_id
  end

  test "rooms report whether they are pinnable" do
    assert rooms(:designers).pinnable?
    assert_not rooms(:david_and_jason).pinnable?
  end

  test "pinning broadcasts the strip and the message pin control to the room" do
    ActionCable.server.pubsub.clear

    @message.pin!

    assert_rendered_turbo_stream_broadcast @room, :messages,
      action: "replace", target: [ @room, :pinned ]
    assert_rendered_turbo_stream_broadcast @room, :messages,
      action: "replace", target: [ @message, :pinning ]
    streams = ActionCable.server.pubsub.broadcasts("#{@room.to_gid_param}:messages").collect { |broadcast| JSON.parse(broadcast) }.join
    assert_select Nokogiri::HTML.fragment(streams),
      %(turbo-stream[action="update"][targets="[data-room-pinning-id='#{@room.id}'] .message__pin-label"])
  end

  test "unpinning broadcasts the cleared strip" do
    @message.pin!
    ActionCable.server.pubsub.clear

    @message.unpin!

    assert_rendered_turbo_stream_broadcast @room, :messages,
      action: "replace", target: [ @room, :pinned ]
  end
end
