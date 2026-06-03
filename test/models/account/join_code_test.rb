require "test_helper"

class Account::JoinCodeTest < ActiveSupport::TestCase
  test "generates base58 formatted code on creation" do
    join_code = Account::JoinCode.create!(account: accounts(:signal))
    assert_match /\A[A-HJ-NP-Za-km-z1-9]{4}-[A-HJ-NP-Za-km-z1-9]{4}-[A-HJ-NP-Za-km-z1-9]{4}\z/, join_code.code
  end

  test "code excludes confusing characters (0, O, I, l)" do
    join_code = Account::JoinCode.new(account: accounts(:signal))
    join_code.send(:generate_code)
    refute_match /[0OIl]/, join_code.code.gsub("-", "")
  end

  test "active when usage_limit is nil (unlimited)" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: nil, usage_count: 1000)
    assert join_code.active?
    assert join_code.unlimited?
  end

  test "active when usage_count is below usage_limit" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: 10, usage_count: 5)
    assert join_code.active?
  end

  test "inactive when usage_count reaches usage_limit" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: 10, usage_count: 10)
    refute join_code.active?
  end

  test "redeem increments usage_count" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: nil, usage_count: 0)

    assert_changes -> { join_code.reload.usage_count }, from: 0, to: 1 do
      assert join_code.redeem
    end
  end

  test "redeem returns false when inactive" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: 1, usage_count: 1)

    assert_no_changes -> { join_code.reload.usage_count } do
      refute join_code.redeem
    end
  end

  test "regenerate_code generates new code and resets usage_count" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_count: 5)
    old_code = join_code.code

    join_code.regenerate_code

    assert_not_equal old_code, join_code.code
    assert_equal 0, join_code.usage_count
  end

  test "used? reflects whether the code has any usage" do
    join_code = account_join_codes(:signal)

    join_code.update!(usage_count: 0)
    refute join_code.used?

    join_code.update!(usage_count: 1)
    assert join_code.used?
  end

  test "usage_display says 'Never used' when usage_count is zero" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: nil, usage_count: 0)
    assert_equal "Never used", join_code.usage_display
  end

  test "usage_display shows count for unlimited" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: nil, usage_count: 42)
    assert_equal "42 uses", join_code.usage_display
  end

  test "usage_display shows count and limit for limited" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: 100, usage_count: 42)
    assert_equal "42 uses of 100", join_code.usage_display
  end

  test "expiry_display rounds remaining time up to whole days" do
    join_code = account_join_codes(:signal)

    join_code.update!(expires_at: 30.days.from_now)
    assert_equal "Expires in 30 days", join_code.expiry_display

    join_code.update!(expires_at: 1.hour.from_now)
    assert_equal "Expires in 1 day", join_code.expiry_display
  end

  test "expiry_display is nil when there is nothing to show" do
    join_code = account_join_codes(:signal)

    join_code.update!(expires_at: nil)
    assert_nil join_code.expiry_display

    join_code.update!(expires_at: 1.hour.ago)
    assert_nil join_code.expiry_display
  end

  test "global? returns true when user_id is nil" do
    join_code = account_join_codes(:signal)
    assert join_code.global?
    refute join_code.personal?
  end

  test "personal? returns true when user_id is present" do
    join_code = account_join_codes(:signal_personal)
    assert join_code.personal?
    refute join_code.global?
    assert_equal users(:david), join_code.user
  end

  test "expired? returns true when expires_at is in the past" do
    join_code = account_join_codes(:signal)
    join_code.update!(expires_at: 1.hour.ago)
    assert join_code.expired?
    refute join_code.active?
  end

  test "expired? returns false when expires_at is in the future" do
    join_code = account_join_codes(:signal)
    join_code.update!(expires_at: 1.hour.from_now)
    refute join_code.expired?
    assert join_code.active?
  end

  test "personal invite sets default expiration on create" do
    join_code = Account::JoinCode.create!(account: accounts(:signal), user: users(:david))
    assert join_code.expires_at.present?
    assert join_code.expires_at > Time.current
    assert join_code.expires_at <= Account::JoinCode::DEFAULT_EXPIRATION.from_now + 1.second
  end

  test "bot invites do not get a default expiration (active until consumed or replaced)" do
    join_code = Account::JoinCode.create!(account: accounts(:signal), kind: :bot)
    assert_nil join_code.expires_at
  end

  test "global invite gets the longer default expiration on create" do
    join_code = Account::JoinCode.create!(account: accounts(:signal))
    assert join_code.expires_at.present?
    assert join_code.expires_at > Account::JoinCode::DEFAULT_EXPIRATION.from_now,
      "global code should outlive the personal default"
    assert join_code.expires_at <= Account::JoinCode::DEFAULT_GLOBAL_EXPIRATION.from_now + 1.second
  end

  test "regenerate_code resets expires_at to a fresh default lifetime" do
    join_code = account_join_codes(:signal)
    join_code.update!(expires_at: 1.minute.from_now)

    join_code.regenerate_code

    assert join_code.expires_at > Account::JoinCode::DEFAULT_EXPIRATION.from_now,
      "regenerate must restore a global code's lifetime"
    assert join_code.expires_at <= Account::JoinCode::DEFAULT_GLOBAL_EXPIRATION.from_now + 1.second
  end

  test "regenerate_code on a personal code resets expires_at to the personal default" do
    join_code = account_join_codes(:signal_personal)
    join_code.update!(expires_at: 1.minute.from_now)

    join_code.regenerate_code

    assert join_code.expires_at > Time.current
    assert join_code.expires_at <= Account::JoinCode::DEFAULT_EXPIRATION.from_now + 1.second,
      "personal regenerate must not stretch to the longer global lifetime"
  end

  test "expiring? reflects whether expires_at is set" do
    join_code = account_join_codes(:signal)

    join_code.update!(expires_at: 1.hour.from_now)
    assert join_code.expiring?

    join_code.update!(expires_at: nil)
    refute join_code.expiring?
  end

  test "toggle_expiration clears the expiry when the code is expiring" do
    join_code = account_join_codes(:signal)
    join_code.update!(expires_at: 30.days.from_now)

    join_code.toggle_expiration

    assert_nil join_code.expires_at
    refute join_code.expired?
  end

  test "toggle_expiration sets a fresh default expiry when the code never expires" do
    join_code = account_join_codes(:signal)
    join_code.update!(expires_at: nil)

    join_code.toggle_expiration

    assert join_code.expires_at.present?
    assert join_code.expires_at <= Account::JoinCode::DEFAULT_GLOBAL_EXPIRATION.from_now + 1.second
  end

  test "regenerate_code keeps a never-expires code permanent" do
    join_code = account_join_codes(:signal)
    join_code.update!(expires_at: nil)
    old_code = join_code.code

    join_code.regenerate_code

    assert_not_equal old_code, join_code.code
    assert_nil join_code.expires_at, "regenerate must preserve the never-expires setting"
  end

  test "redeem! raises InactiveCodeError when exhausted" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: 1, usage_count: 1)

    assert_raises Account::JoinCode::InactiveCodeError do
      join_code.redeem!
    end
  end

  test "redeem! raises InactiveCodeError when expired" do
    join_code = account_join_codes(:signal)
    join_code.update!(expires_at: 1.hour.ago)

    assert_raises Account::JoinCode::InactiveCodeError do
      join_code.redeem!
    end
  end

  test "redeem! increments usage_count when active" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: nil, usage_count: 0)

    assert_changes -> { join_code.reload.usage_count }, from: 0, to: 1 do
      join_code.redeem!
    end
  end

  test "redeem_if increments and returns the block result when active and block returns truthy" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: nil, usage_count: 0)

    assert_changes -> { join_code.reload.usage_count }, from: 0, to: 1 do
      assert_equal :ok, join_code.redeem_if { :ok }
    end
  end

  test "redeem_if skips increment and returns false when block returns falsy" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: nil, usage_count: 0)

    assert_no_changes -> { join_code.reload.usage_count } do
      assert_equal false, join_code.redeem_if { false }
    end
  end

  test "redeem_if short-circuits and never runs the block when inactive" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: 1, usage_count: 1)

    block_ran = false
    assert_no_changes -> { join_code.reload.usage_count } do
      assert_equal false, join_code.redeem_if { block_ran = true }
    end
    refute block_ran, "block must not run when the code is inactive"
  end

  test "redeem_if rolls back the increment when the block raises" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: nil, usage_count: 0)

    assert_no_changes -> { join_code.reload.usage_count } do
      assert_raises(RuntimeError) do
        join_code.redeem_if { raise "boom" }
      end
    end
  end
end
