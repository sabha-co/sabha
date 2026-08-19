require "test_helper"

class Accounts::Bots::KeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "update" do
    assert_changes -> { users(:bender).reload.bot_key_digest } do
      put account_bot_key_url(users(:bender)), as: :turbo_stream
    end

    assert_response :success
    assert_match "New bearer key", @response.body
    assert_match(/sabha_bot_/, @response.body)
  end
end
