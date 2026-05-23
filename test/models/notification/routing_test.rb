require "test_helper"

class Notification::RoutingTest < ActiveSupport::TestCase
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
