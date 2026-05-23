require "test_helper"

class Account::JoinableTest < ActiveSupport::TestCase
  test "new accounts get a join code" do
    Account.destroy_all
    account = Account.create!(name: "Chat")
    assert_match /\w{4}-\w{4}-\w{4}/, account.join_code.code
  end

  test "accounts can reset join code" do
    assert_changes -> { accounts(:signal).join_code.reload.code } do
      accounts(:signal).reset_join_code
    end
  end

  test "join_code lazily regenerates an expired global code" do
    account = accounts(:signal)
    stale = account.join_code
    stale.update!(expires_at: 1.hour.ago, usage_count: 5)
    old_code = stale.code

    fresh = account.join_code

    assert_not_equal old_code, fresh.code
    assert fresh.expires_at > Time.current
    assert_equal 0, fresh.usage_count
  end
end
