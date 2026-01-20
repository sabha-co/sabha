require "test_helper"

class Messages::UnreadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @room = rooms(:watercooler)
    @message = @room.messages.create!(creator: users(:jason), body: "Test message")
    @membership = @room.memberships.find_by(user: users(:david))
    @membership.update!(unread_at: nil)
  end

  test "create marks message as unread" do
    assert @membership.read?

    post room_message_unreads_url(@room, @message, format: :turbo_stream)

    assert_response :success
    @membership.reload
    assert @membership.unread?
    assert_equal @message.created_at, @membership.unread_at
  end
end
