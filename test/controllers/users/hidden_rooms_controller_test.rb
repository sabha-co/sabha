require "test_helper"

class Users::HiddenRoomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index lists rooms the current user has made invisible" do
    memberships(:david_pets).update!(involvement: :invisible)

    get user_hidden_rooms_url

    assert_response :success
    assert_match rooms(:pets).name, @response.body
  end

  test "index renders an empty state when nothing is hidden" do
    get user_hidden_rooms_url

    assert_response :success
    assert_match "No hidden rooms", @response.body
  end
end
