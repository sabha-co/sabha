require "test_helper"

# Guards the fix for full-page reloads on every navigation: Turnstile's script
# carries both data-turbo-track="reload" and data-turbo-temporary, a contradiction
# that makes Turbo see a tracked-element mismatch on every visit and fall back to
# a full reload (which defeats the turbo-permanent sidebar). The script must load
# only where the widget renders — the signup page — and nowhere else.
class TurboDriveNavigationTest < ActionDispatch::IntegrationTest
  test "chat pages omit the turnstile script so Turbo Drive can keep the shell" do
    sign_in :kevin
    get room_url(rooms(:designers))

    assert_response :success
    assert_no_match(/data-turbo-temporary/, response.body,
      "a data-turbo-temporary + data-turbo-track element forces a full reload on every navigation")
    assert_no_match(/cf-turnstile|turnstile/i, response.body)
  end

  test "the signup page still loads the turnstile script" do
    get join_url(Current.account.join_code.code)

    assert_response :success
    assert_select "script[data-turbo-track=reload][data-turbo-temporary]", count: 1
  end
end
