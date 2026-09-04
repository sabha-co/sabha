require "test_helper"

class DesktopRenderingTest < ActionDispatch::IntegrationTest
  setup do
    host! "once.sabha.test"
    sign_in :david
  end

  test "desktop client requests omit webpush enrollment ui" do
    get user_sidebar_url(user_id: "me"), headers: { "Sabha-Desktop-Client" => "1" }

    assert_response :success
    assert_select "#notification_bell_container", count: 0
  end

  test "browser requests still render webpush enrollment ui" do
    get user_sidebar_url(user_id: "me")

    assert_response :success
    assert_select "#notification_bell_container", count: 1
  end
end
