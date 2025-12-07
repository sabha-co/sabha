require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "user does not prevent very long passwords" do
    users(:david).update(password: "secret" * 50)
    assert users(:david).valid?
  end

  test "creating users grants membership to the open rooms" do
    assert_difference -> { Membership.count }, +Rooms::Open.count do
      create_new_user
    end
  end

  test "deactivating a user deletes push subscriptions, searches, deactivates memberships for non-direct rooms, and changes their email address" do
    user = users(:david)
    membership_count_before = user.memberships.without_direct_rooms.count

    assert_no_difference -> { Membership.count } do  # Memberships are soft-deleted (active: false), not removed
    assert_difference -> { Membership.active.count }, -membership_count_before do  # But active count decreases
    assert_difference -> { Push::Subscription.count }, -user.push_subscriptions.count do
    assert_difference -> { Search.count }, -user.searches.count do
      SecureRandom.stubs(:uuid).returns("2e7de450-cf04-4fa8-9b02-ff5ab2d733e7")
      user.deactivate
      assert_equal "david-deactivated-2e7de450-cf04-4fa8-9b02-ff5ab2d733e7@37signals.com", user.reload.email_address
    end
    end
    end
    end
  end

  test "deactivating a user deletes their sessions" do
    assert_changes -> { users(:david).sessions.count }, from: 1, to: 0 do
      users(:david).deactivate
    end
  end

  test "email validation rejects invalid format" do
    user = User.new(name: "Test", email_address: "not-an-email", password: "secret123456")
    assert_not user.valid?
    assert_includes user.errors[:email_address], "is invalid"
  end

  test "email validation accepts valid format" do
    user = User.new(name: "Test", email_address: "valid@example.com", password: "secret123456")
    assert user.valid?
  end

  test "email validation accepts emails with plus signs" do
    user = User.new(name: "Test", email_address: "valid+tag@example.com", password: "secret123456")
    assert user.valid?
  end

  private
    def create_new_user
      User.create!(name: "User", email_address: "user@example.com", password: "secret123456")
    end
end
