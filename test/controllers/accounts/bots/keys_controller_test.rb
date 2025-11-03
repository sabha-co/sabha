require "test_helper"

class Accounts::Bots::KeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "update" do
    assert_changes -> { users(:bender).reload.bot_token } do
      put account_bot_key_url(users(:bender))
      assert_redirected_to account_bots_url
    end
  end
end
