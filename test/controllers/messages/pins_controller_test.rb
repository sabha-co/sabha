require "test_helper"

class Messages::PinsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @room = rooms(:designers)
    @message = messages(:first)
  end

  test "staff pins a message" do
    sign_in :david

    post room_message_pin_url(@room, @message), as: :turbo_stream

    assert_response :success
    assert_equal @message, @room.reload.pinned_message
  end

  test "pinning replaces the room's existing pin" do
    sign_in :david
    @message.pin!

    post room_message_pin_url(@room, messages(:second)), as: :turbo_stream

    assert_equal messages(:second), @room.reload.pinned_message
    assert_not @message.reload.pinned?
  end

  test "staff unpins a message" do
    sign_in :david
    @message.pin!

    delete room_message_pin_url(@room, @message), as: :turbo_stream

    assert_nil @room.reload.pinned_message
  end

  test "a non-staff member cannot pin" do
    sign_in :kevin

    post room_message_pin_url(@room, @message), as: :turbo_stream

    assert_response :forbidden
    assert_nil @room.reload.pinned_message
  end

  test "the room page shows the pinned message in a strip" do
    sign_in :david
    @message.pin!

    get room_url(@room)

    assert_response :success
    assert_select ".pinned-bar .pinned-bar__label", text: "Pinned"
    assert_select ".pinned-bar .pinned-bar__text", text: /#{Regexp.escape(@message.plain_text_body)}/
  end

  test "pin menu labels state whether pinning replaces the current pin" do
    cache_store = ActionController::Base.cache_store
    perform_caching = ActionController::Base.perform_caching
    ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.perform_caching = true

    sign_in :david

    get room_url(@room)
    assert_select "##{dom_id(@message, :pinning)}", text: "Pin to room"

    @message.pin!

    get room_url(@room)
    assert_select "##{dom_id(@message, :pinning)}", text: "Unpin from room"
    assert_select "##{dom_id(messages(:second), :pinning)}", text: "Pin instead of current"
  ensure
    ActionController::Base.cache_store = cache_store
    ActionController::Base.perform_caching = perform_caching
  end

  test "cannot pin a message in a direct room" do
    sign_in :david
    dm = rooms(:david_and_jason)
    message = dm.messages.create!(creator: users(:david), body: "hi", client_message_id: "pin_dm_test")

    post room_message_pin_url(dm, message), as: :turbo_stream

    assert_response :forbidden
    assert_nil dm.reload.pinned_message
  end
end
