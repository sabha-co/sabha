require "test_helper"

class Notification::RoutingTest < ActiveSupport::TestCase
  test "ACTIVITY_TYPES is the dispatcher's full vocabulary" do
    assert_equal %i[mention direct_message everyone_room_message thread_reply boost],
      Notification::Routing::ACTIVITY_TYPES
    assert Notification::Routing::ACTIVITY_TYPES.frozen?
  end

  test "IN_APP_ROW_TYPES contains the three persisted activity types" do
    assert_equal %i[mention thread_reply boost], Notification::Routing::IN_APP_ROW_TYPES
    assert Notification::Routing::IN_APP_ROW_TYPES.frozen?
  end

  test "PUSH_TYPES excludes :boost (push routes the underlying message instead)" do
    assert_equal %i[mention direct_message everyone_room_message thread_reply],
      Notification::Routing::PUSH_TYPES
    assert Notification::Routing::PUSH_TYPES.frozen?
  end

  test "EMAIL_TYPES is mention + direct_message only" do
    assert_equal %i[mention direct_message], Notification::Routing::EMAIL_TYPES
    assert Notification::Routing::EMAIL_TYPES.frozen?
  end

  test "every IN_APP_ROW_TYPES, PUSH_TYPES, EMAIL_TYPES entry is in ACTIVITY_TYPES" do
    [
      Notification::Routing::IN_APP_ROW_TYPES,
      Notification::Routing::PUSH_TYPES,
      Notification::Routing::EMAIL_TYPES
    ].each do |subset|
      assert subset.all? { |type| Notification::Routing::ACTIVITY_TYPES.include?(type) },
        "Subset #{subset.inspect} contains a type not in ACTIVITY_TYPES"
    end
  end
end
