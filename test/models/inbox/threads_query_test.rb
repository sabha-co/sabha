require "test_helper"

class Inbox::ThreadsQueryTest < ActiveSupport::TestCase
  setup do
    @user = users(:jason)
    @parent_room = rooms(:hq)
    @parent_message = @parent_room.messages.create!(body: "Parent", creator: users(:david), client_message_id: "tq-parent")
    @thread = Rooms::Thread.find_or_create_for(@parent_message, creator: @user)
    @thread.messages.create!(body: "Reply", creator: @user, client_message_id: "tq-reply")
  end

  test "returns the parent message of an accessible active thread" do
    assert_includes Inbox::ThreadsQuery.new(@user).call, @parent_message
  end

  test "excludes a deactivated thread (active = TRUE boolean holds on every adapter)" do
    @thread.update!(active: false)

    assert_not_includes Inbox::ThreadsQuery.new(@user).call, @parent_message
  end
end
