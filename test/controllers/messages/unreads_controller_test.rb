require "test_helper"

class Messages::UnreadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @room = rooms(:watercooler)
    @message = @room.messages.create!(creator: users(:jason), body: "Test message")
    @membership = @room.memberships.find_by(user: users(:david))
    catch_up @membership
  end

  test "create marks message as unread" do
    assert @membership.read?

    post room_message_unreads_url(@room, @message, format: :turbo_stream)

    assert_response :success
    @membership.reload
    assert @membership.unread?
    assert_equal @message, @membership.first_unread_message
  end
end
