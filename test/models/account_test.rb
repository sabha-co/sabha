require "test_helper"

class AccountTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:signal)
  end

  test "auth_method_value defaults to password when ENV not set" do
    original_env = ENV["AUTH_METHOD"]
    begin
      ENV.delete("AUTH_METHOD")
      assert_equal "password", @account.auth_method_value
    ensure
      ENV["AUTH_METHOD"] = original_env if original_env
    end
  end

  test "auth_method_value returns ENV value when set" do
    original_env = ENV["AUTH_METHOD"]
    begin
      ENV["AUTH_METHOD"] = "otp"
      assert_equal "otp", @account.auth_method_value
    ensure
      if original_env.nil?
        ENV.delete("AUTH_METHOD")
      else
        ENV["AUTH_METHOD"] = original_env
      end
    end
  end

  test "auth_method_value falls back to password for invalid ENV value" do
    original_env = ENV["AUTH_METHOD"]
    begin
      ENV["AUTH_METHOD"] = "invalid"
      assert_equal "password", @account.auth_method_value
    ensure
      if original_env.nil?
        ENV.delete("AUTH_METHOD")
      else
        ENV["AUTH_METHOD"] = original_env
      end
    end
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

  test "settings allow_users_to_create_invite_links defaults to true" do
    assert @account.settings.allow_users_to_create_invite_links?
  end

  test "settings allow_users_to_create_invite_links can be toggled" do
    @account.settings.allow_users_to_create_invite_links = false
    assert_not @account.settings.allow_users_to_create_invite_links?

    @account.update!(settings: { "allow_users_to_create_invite_links" => "false" })
    assert_not @account.reload.settings.allow_users_to_create_invite_links?

    @account.settings.allow_users_to_create_invite_links = true
    assert @account.settings.allow_users_to_create_invite_links?

    @account.update!(settings: { "allow_users_to_create_invite_links" => "true" })
    assert @account.reload.settings.allow_users_to_create_invite_links?
  end

  test "disabling invite links destroys all personal invite links" do
    personal_link = account_join_codes(:signal_personal)
    global_link = account_join_codes(:signal)

    assert Account::JoinCode.exists?(personal_link.id)
    assert Account::JoinCode.exists?(global_link.id)

    @account.update!(settings: { "allow_users_to_create_invite_links" => "false" })

    assert_not Account::JoinCode.exists?(personal_link.id), "Personal invite link should be destroyed"
    assert Account::JoinCode.exists?(global_link.id), "Global invite link should remain"
  end
end
