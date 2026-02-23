require "test_helper"

class NotificationsHelperTest < ActionView::TestCase
  setup do
    @david = users(:david)
    @jason = users(:jason)
    @jz = users(:jz)
    @room = rooms(:pets)
  end

  test "groups consecutive boost notifications on the same message" do
    message = @room.messages.create!(body: "Boost me", creator: @david, client_message_id: "group_test_1")
    b1 = message.boosts.create!(content: "🔥", booster: @jason)
    b2 = message.boosts.create!(content: "💯", booster: @jz)

    notifications = Notification.where(message: message, activity_type: "boost").with_message_and_creator.ordered.to_a
    grouped = group_boost_notifications(notifications)

    assert_equal 1, grouped.size
    assert_instance_of Notification::BoostGroup, grouped.first
    assert_equal 2, grouped.first.actors.size
    assert_equal %w[🔥 💯], grouped.first.boost_contents
  end

  test "does not group boost notifications on different messages" do
    m1 = @room.messages.create!(body: "First", creator: @david, client_message_id: "group_diff_1")
    m2 = @room.messages.create!(body: "Second", creator: @david, client_message_id: "group_diff_2")
    m1.boosts.create!(content: "🔥", booster: @jason)
    m2.boosts.create!(content: "💯", booster: @jason)

    notifications = Notification.where(activity_type: "boost", message_id: [ m1.id, m2.id ]).with_message_and_creator.ordered.to_a
    grouped = group_boost_notifications(notifications)

    assert_equal 2, grouped.size
    assert grouped.all? { |g| g.is_a?(Notification::BoostGroup) }
  end

  test "does not group boosts separated by a mention" do
    message = @room.messages.create!(body: "Boost me", creator: @david, client_message_id: "group_split_1")
    b1 = message.boosts.create!(content: "🔥", booster: @jason)

    # Create a mention notification between the two boosts
    mention_msg = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "group_split_mention"
    )

    b2 = message.boosts.create!(content: "💯", booster: @jz)

    notifications = Notification.where(user: @david).with_message_and_creator.ordered.to_a
    grouped = group_boost_notifications(notifications)

    # Should be: BoostGroup(b1), mention, BoostGroup(b2) — not grouped together
    assert_equal 3, grouped.size
  end

  test "mentions and thread replies pass through ungrouped" do
    m1 = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "passthrough_1"
    )
    m2 = @room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: @jason,
      client_message_id: "passthrough_2"
    )

    notifications = Notification.where(user: @david, activity_type: "mention").with_message_and_creator.ordered.to_a
    grouped = group_boost_notifications(notifications)

    assert_equal 2, grouped.size
    assert grouped.all? { |n| n.is_a?(Notification) }
  end
end
