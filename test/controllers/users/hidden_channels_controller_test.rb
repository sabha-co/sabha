require "test_helper"

class Users::HiddenChannelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index lists channels the current user has made invisible" do
    memberships(:david_pets).update!(involvement: :invisible)

    get user_hidden_channels_url

    assert_response :success
    assert_match channels(:pets).name, @response.body
    # The hidden-channel append broadcast targets #hidden_channels_list, so the list
    # container must render with that id and hold each hidden channel's row.
    assert_select "#hidden_channels_list ##{dom_id(channels(:pets), :hidden_channel)}"
  end

  test "index renders an empty state when nothing is hidden" do
    get user_hidden_channels_url

    assert_response :success
    assert_match "No hidden channels", @response.body
  end
end
