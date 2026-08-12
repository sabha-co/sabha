require "test_helper"

class Inbox::ActivityQueryTest < ActiveSupport::TestCase
  setup do
    @user = users(:david)
    @actor = users(:jason)
    @message = rooms(:pets).messages.create!(body: "hi", creator: @actor, client_message_id: "aq-msg")
    @mention = Notification.create!(user: @user, message: @message, actor: @actor, activity_type: "mention")
    @reply = Notification.create!(user: @user, message: @message, actor: @actor, activity_type: "thread_reply")
    @boost = Notification.create!(user: @user, message: @message, actor: @actor, activity_type: "boost")
  end

  test "no filter returns every activity type" do
    result = Inbox::ActivityQuery.new(@user).call

    assert_includes result, @mention
    assert_includes result, @reply
    assert_includes result, @boost
  end

  test "the mentions filter returns only mention notifications" do
    assert_equal [ @mention ], Inbox::ActivityQuery.new(@user, filter: "mentions").call.to_a
  end

  test "the replies filter returns only thread-reply notifications" do
    assert_equal [ @reply ], Inbox::ActivityQuery.new(@user, filter: "replies").call.to_a
  end

  test "the reactions filter returns only boost notifications" do
    assert_equal [ @boost ], Inbox::ActivityQuery.new(@user, filter: "reactions").call.to_a
  end

  test "an unknown filter is ignored and returns everything" do
    assert_equal 3, Inbox::ActivityQuery.new(@user, filter: "bogus").call.count
  end
end
