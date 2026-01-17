require "test_helper"

class Account::JoinCodeTest < ActiveSupport::TestCase
  test "generates base58 formatted code on creation" do
    join_code = Account::JoinCode.create!(account: accounts(:signal))
    assert_match /\A[A-HJ-NP-Za-km-z1-9]{4}-[A-HJ-NP-Za-km-z1-9]{4}-[A-HJ-NP-Za-km-z1-9]{4}\z/, join_code.code
  end

  test "code excludes confusing characters (0, O, I, l)" do
    100.times do
      join_code = Account::JoinCode.new(account: accounts(:signal))
      join_code.send(:generate_code)
      refute_match /[0OIl]/, join_code.code.gsub("-", "")
    end
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

  test "usage_display shows count for unlimited" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: nil, usage_count: 42)
    assert_equal "42 uses", join_code.usage_display
  end

  test "usage_display shows count/limit for limited" do
    join_code = account_join_codes(:signal)
    join_code.update!(usage_limit: 100, usage_count: 42)
    assert_equal "42/100 uses", join_code.usage_display
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

  test "expired? returns false when expires_at is nil" do
    join_code = account_join_codes(:signal)
    join_code.update!(expires_at: nil)
    refute join_code.expired?
  end

  test "personal invite sets default expiration on create" do
    join_code = Account::JoinCode.create!(account: accounts(:signal), user: users(:david))
    assert join_code.expires_at.present?
    assert join_code.expires_at > Time.current
    assert join_code.expires_at <= Account::JoinCode::DEFAULT_EXPIRATION.from_now + 1.second
  end

  test "global invite does not set default expiration" do
    join_code = Account::JoinCode.create!(account: accounts(:signal))
    assert_nil join_code.expires_at
  end

  test "redeem returns false when expired" do
    join_code = account_join_codes(:signal)
    join_code.update!(expires_at: 1.hour.ago)

    assert_no_changes -> { join_code.reload.usage_count } do
      refute join_code.redeem
    end
  end
end
