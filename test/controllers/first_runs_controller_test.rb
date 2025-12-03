require "test_helper"

class FirstRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Disable FK checks to clean up all data
    ActiveRecord::Base.connection.execute("PRAGMA foreign_keys = OFF")
    Membership.delete_all
    Mention.delete_all
    Boost.delete_all
    Bookmark.delete_all
    Message.delete_all
    Room.delete_all
    Session.delete_all
    AuthToken.delete_all
    Push::Subscription.delete_all
    Webhook.delete_all
    Search.delete_all
    Block.delete_all
    User.delete_all
    Account.delete_all
    ActiveRecord::Base.connection.execute("PRAGMA foreign_keys = ON")
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
