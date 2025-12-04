require "test_helper"

class AccountTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:signal)
  end

  test "auth_method defaults to password" do
    @account.update!(auth_method: nil)
    assert_equal "password", @account.auth_method_value
  end

  test "auth_method_value returns database value" do
    @account.update!(auth_method: "otp")
    assert_equal "otp", @account.auth_method_value
  end

  test "validates auth_method inclusion" do
    @account.auth_method = "invalid"
    assert_not @account.valid?
    assert_includes @account.errors[:auth_method], "must be 'password' or 'otp'"
  end

  test "new account has default auth_method" do
    account = Account.new(name: "New Account", join_code: "NEW-CODE")
    assert_equal "password", account.auth_method
  end

  test "settings restrict_room_creation_to_administrators defaults to false" do
    assert_not @account.settings.restrict_room_creation_to_administrators?
  end

  test "settings restrict_room_creation_to_administrators can be toggled" do
    @account.settings.restrict_room_creation_to_administrators = true
    assert @account.settings.restrict_room_creation_to_administrators?
    assert_equal true, @account[:settings]["restrict_room_creation_to_administrators"]

    @account.update!(settings: { "restrict_room_creation_to_administrators" => "true" })
    assert @account.reload.settings.restrict_room_creation_to_administrators?

    @account.settings.restrict_room_creation_to_administrators = false
    assert_not @account.settings.restrict_room_creation_to_administrators?
    assert_equal false, @account[:settings]["restrict_room_creation_to_administrators"]

    @account.update!(settings: { "restrict_room_creation_to_administrators" => "false" })
    assert_not @account.reload.settings.restrict_room_creation_to_administrators?
  end

  test "settings restrict_direct_messages_to_administrators defaults to false" do
    assert_not @account.settings.restrict_direct_messages_to_administrators?
  end

  test "settings restrict_direct_messages_to_administrators can be toggled" do
    @account.settings.restrict_direct_messages_to_administrators = true
    assert @account.settings.restrict_direct_messages_to_administrators?

    @account.update!(settings: { "restrict_direct_messages_to_administrators" => "true" })
    assert @account.reload.settings.restrict_direct_messages_to_administrators?

    @account.settings.restrict_direct_messages_to_administrators = false
    assert_not @account.settings.restrict_direct_messages_to_administrators?

    @account.update!(settings: { "restrict_direct_messages_to_administrators" => "false" })
    assert_not @account.reload.settings.restrict_direct_messages_to_administrators?
  end
end
