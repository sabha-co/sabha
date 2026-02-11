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

  test "update redirects to sign in when the token is invalid" do
    put session_transfer_url("garbage-token")

    assert_redirected_to new_session_url
    assert_equal "That sign-in link is invalid or has expired.", flash[:alert]
  end

  test "update redirects to sign in when the token has expired" do
    user = users(:david)
    transfer_id = user.transfer_id

    travel User::Transferable::TRANSFER_LINK_EXPIRY_DURATION + 1.minute

    put session_transfer_url(transfer_id)

    assert_redirected_to new_session_url
    assert_equal "That sign-in link is invalid or has expired.", flash[:alert]
  end

  test "update rejects a deactivated user" do
    user = users(:david)
    transfer_id = user.transfer_id
    user.update!(status: :deactivated)

    put session_transfer_url(transfer_id)

    assert_redirected_to new_session_url
    assert_equal "That sign-in link is invalid or has expired.", flash[:alert]
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "update rejects a banned user" do
    user = users(:david)
    transfer_id = user.transfer_id
    user.update!(status: :banned)

    put session_transfer_url(transfer_id)

    assert_redirected_to new_session_url
    assert_equal "That sign-in link is invalid or has expired.", flash[:alert]
    assert_nil parsed_cookies.signed[:session_token]
  end
end
