require "test_helper"

class FirstRunTest < ActiveSupport::TestCase
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

  test "creating makes first user an administrator" do
    user = create_first_run_user
    assert user.administrator?
  end

  test "first user has access to first room" do
    user = create_first_run_user
    assert user.rooms.one?
  end

  test "first room is an open room" do
    create_first_run_user
    assert Room.first.open?
  end

  private
    def create_first_run_user
      FirstRun.create!({ name: "User", email_address: "user@example.com", password: "secret123456" })
    end
end
