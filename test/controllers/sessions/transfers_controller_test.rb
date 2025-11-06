require "test_helper"

class Sessions::TransfersControllerTest < ActionDispatch::IntegrationTest
  test "show renders when not signed in" do
    get session_transfer_url("some-token")

    assert_response :success
  end

  test "update establishes a session when the code is valid" do
    user = users(:david)

    put session_transfer_url(user.transfer_id)

    assert_redirected_to root_url
    assert parsed_cookies.signed[:session_token]
  end
end
