require "test_helper"

class DesktopRenderingTest < ActionDispatch::IntegrationTest
  DESKTOP_APP_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36 Sabha Desktop/1.0.0"

  setup do
    host! "once.sabha.test"
    sign_in :david
  end

  test "desktop app requests omit webpush enrollment ui" do
    get user_sidebar_url(user_id: "me"), headers: { "User-Agent" => DESKTOP_APP_USER_AGENT }

    assert_response :success
    assert_select "#notification_bell_container", count: 0
  end

  test "browser requests still render webpush enrollment ui" do
    get user_sidebar_url(user_id: "me")

    assert_response :success
    assert_select "#notification_bell_container", count: 1
  end
end
