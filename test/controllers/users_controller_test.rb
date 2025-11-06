require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "show" do
    sign_in :david
    get user_url(users(:david))
    assert_response :ok
  end
end
