require "test_helper"

class Users::AvatarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show initials" do
    get user_avatar_url(users(:kevin).avatar_token)
    assert_select "text", text: "K"
  end

  test "show image with invalid token responds 404" do
    get user_avatar_url("not-a-valid-token")

    assert_response :not_found
  end
end
