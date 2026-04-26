require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  setup { Current.reset }

  test "session= cascades into Current.user" do
    session = sessions(:david_safari)

    Current.session = session

    assert_equal session.user, Current.user
  end

  test "session= nil clears Current.user" do
    Current.session = sessions(:david_safari)
    Current.session = nil

    assert_nil Current.user
  end
end
