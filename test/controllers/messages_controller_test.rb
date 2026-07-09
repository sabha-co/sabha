require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "once.sabha.test"

    sign_in :david
    @room = rooms(:watercooler)
    @messages = @room.messages.ordered.to_a
  end

  test "index returns the last page by default" do
    get room_messages_url(@room)

    assert_response :success
    ensure_messages_present @messages.last
  end

  test "index returns a page before the specified message" do
    get room_messages_url(@room, before: @messages.third)

    assert_response :success
    ensure_messages_present @messages.first, @messages.second
    ensure_messages_not_present @messages.third, @messages.fourth, @messages.fifth
  end

  test "index returns a page after the specified message" do
    get room_messages_url(@room, after: @messages.third)

    assert_response :success
    ensure_messages_present @messages.fourth, @messages.fifth
    ensure_messages_not_present @messages.first, @messages.second, @messages.third
  end

  test "index returns no_content when there are no messages" do
    @room.messages.update_all(active: false)

    get room_messages_url(@room)

    assert_response :no_content
  end

  test "get renders a single message belonging to the user" do
    message = @room.messages.where(creator: users(:david)).first

    get room_message_url(@room, message)

    assert_response :success
    assert_select "##{dom_id(message)}"
  end

  test "creating a message broadcasts the message to the room" do
    post room_messages_url(@room, format: :turbo_stream), params: { message: { body: "New one", client_message_id: 999 } }

    assert_rendered_turbo_stream_broadcast @room, :messages, action: "append", target: [ @room, :messages ] do
      assert_select ".message__body", text: /New one/
      assert_copy_link_button room_at_message_url(@room, Message.last, host: "once.sabha.test")
    end
  end

  test "creating a message publishes one shared room nudge instead of per-user unread broadcasts" do
    # One account-wide publish regardless of member count; each client derives
    # its own unread state from it. No per-user UserUnreadRoomsChannel push and
    # no global "unread_rooms" broadcast (the original thundering-herd fix).
    other_member = @room.memberships.visible.where.not(user: users(:david)).first
    catch_up other_member
    other_member.update!(connected_at: nil)

    nudges = capture_broadcasts(RoomListChannel.broadcasting_for(Account.sole)) do
      assert_no_broadcasts UserUnreadRoomsChannel.broadcasting_for(other_member.user) do
        assert_no_broadcasts "unread_rooms" do
          post room_messages_url(@room, format: :turbo_stream), params: { message: { body: "New one", client_message_id: SecureRandom.uuid } }
        end
      end
    end

    assert_equal 1, nudges.size
    assert_equal @room.id, nudges.first["roomId"]
  end

  test "mentioning a user in a room they're not viewing refreshes their sidebar sort metadata" do
    # The shared nudge carries the sidebar sort keys (roomUpdatedAt, roomSize),
    # so a disconnected mentionee's sidebar re-floats the room without a
    # per-user push; their client derives the unread dot from the nudge.
    jason_membership = @room.memberships.find_by(user: users(:jason))
    catch_up jason_membership
    jason_membership.update!(connected_at: nil)

    nudges = capture_broadcasts(RoomListChannel.broadcasting_for(Account.sole)) do
      post room_messages_url(@room, format: :turbo_stream),
        params: { message: { body: "<div>Hey #{mention_attachment_for(:jason)}</div>", client_message_id: SecureRandom.uuid } }
    end

    nudge = nudges.find { |n| n["roomId"] == @room.id }
    assert nudge, "expected a shared room-list nudge carrying the room's sort metadata"
    assert_equal @room.reload.messages_count, nudge["roomSize"]
    assert_equal @room.last_active_at.iso8601, nudge["roomUpdatedAt"]
  end

  test "update updates a message belonging to the user" do
    message = @room.messages.where(creator: users(:david)).first

    # One broadcast to the room's :messages stream, one to the global :inbox stream.
    assert_turbo_stream_broadcasts [ @room, :messages ], count: 1 do
      assert_turbo_stream_broadcasts [ Account.sole, :inbox ], count: 1 do
        put room_message_url(@room, message), params: { message: { body: "Updated body" } }
      end
    end

    assert_redirected_to room_message_url(@room, message)
    assert_equal "Updated body", message.reload.plain_text_body
  end

  test "destroy soft-deletes a message belonging to the user" do
    message = @room.messages.where(creator: users(:david)).first

    # Soft deletion - count stays same but active count decreases.
    # One remove broadcast to the room's :messages stream, one to the global :inbox stream.
    assert_difference -> { Message.active.count }, -1 do
      assert_turbo_stream_broadcasts [ @room, :messages ], count: 1 do
        assert_turbo_stream_broadcasts [ Account.sole, :inbox ], count: 1 do
          delete room_message_url(@room, message, format: :turbo_stream)
          assert_response :success
        end
      end
    end
    assert_not message.reload.active?
  end

  test "ensure non-admin can't update a message belonging to another user" do
    sign_in :jz
    assert_not users(:jz).administrator?

    room = rooms(:designers)
    message = room.messages.where(creator: users(:jason)).first

    put room_message_url(room, message), params: { message: { body: "Updated body" } }
    assert_response :forbidden
  end

  test "ensure non-admin can't destroy a message belonging to another user" do
    sign_in :jz
    assert_not users(:jz).administrator?

    room = rooms(:designers)
    message = room.messages.where(creator: users(:jason)).first

    delete room_message_url(room, message, format: :turbo_stream)
    assert_response :forbidden
  end

  test "creating a message with a direct-uploaded attachment via signed_id" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("hello world"),
      filename: "test.txt",
      content_type: "text/plain"
    )

    assert_difference -> { Message.count }, 1 do
      post room_messages_url(@room, format: :turbo_stream),
        params: { message: { attachment: blob.signed_id, client_message_id: "test-123" } }
    end

    assert Message.last.attachment.attached?
    assert_equal "test.txt", Message.last.attachment.filename.to_s
  end

  test "mentioning a bot triggers webhook for that bot" do
    WebMock.stub_request(:post, webhooks(:bender).url).to_return(status: 200)

    assert_enqueued_jobs 1, only: Bot::WebhookJob do
      post room_messages_url(@room, format: :turbo_stream), params: { message: {
        body: "<div>Hey #{mention_attachment_for(:bender)}</div>", client_message_id: 999 } }
    end
  end

  private
    def ensure_messages_present(*messages, count: 1)
      messages.each do |message|
        assert_select "#" + dom_id(message), count:
      end
    end

    def ensure_messages_not_present(*messages)
      ensure_messages_present *messages, count: 0
    end

    def assert_copy_link_button(url)
      assert_select ".btn[data-copy-to-clipboard-content-value='#{url}']", text: /Copy link/
    end
end
