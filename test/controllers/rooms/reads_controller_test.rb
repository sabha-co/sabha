require "test_helper"

class Rooms::ReadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @membership = memberships(:david_designers)
  end

  test "create advances the read cursor to the room head and clears the badge" do
    @membership.update!(marked_unread: true, unread_notifications_count: 3)

    post room_read_url(@membership.room)

    @membership.reload
    assert @membership.read?
    assert_not @membership.marked_unread?
    assert_equal 0, @membership.unread_notifications_count
  end

  test "create redirects back to the room over html" do
    post room_read_url(@membership.room)

    assert_redirected_to room_url(@membership.room)
  end

  test "create requires membership of the room" do
    assert_raises ActiveRecord::RecordNotFound do
      post room_read_url(rooms(:help_desk))
    end
  end
end
