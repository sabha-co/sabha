require "test_helper"

class FirstRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Account.destroy_all
    User.destroy_all
    Room.destroy_all
  end

  test "new is permitted when no other users exit" do
    get first_run_url
    assert_response :success
  end

  test "new is not permitted when account exist" do
    Account.create!(name: "Chat")

    get first_run_url
    assert_redirected_to root_url
  end

  test "create" do
    assert_difference -> { Room.count }, 1 do
      assert_difference -> { User.count }, 1 do
        post first_run_url, params: { account: { name: "37signals" }, user: { name: "New Person", email_address: "new@37signals.com", password: "secret123456" } }
      end
    end

    assert_redirected_to root_url

    assert parsed_cookies.signed[:session_token]
  end
end
