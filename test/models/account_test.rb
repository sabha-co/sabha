require "test_helper"

class AccountTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:signal)
  end

  test "auth_method defaults to password when ENV not set" do
    original_env = ENV["AUTH_METHOD"]
    begin
      ENV.delete("AUTH_METHOD")
      assert_equal "password", @account.auth_method
      assert @account.password_auth?
      assert_not @account.otp_auth?
      assert_not @account.sso_auth?
    ensure
      ENV["AUTH_METHOD"] = original_env if original_env
    end
  end

  test "auth_method returns otp when set" do
    original_env = ENV["AUTH_METHOD"]
    begin
      ENV["AUTH_METHOD"] = "otp"
      assert_equal "otp", @account.auth_method
      assert @account.otp_auth?
      assert_not @account.password_auth?
      assert_not @account.sso_auth?
    ensure
      if original_env.nil?
        ENV.delete("AUTH_METHOD")
      else
        ENV["AUTH_METHOD"] = original_env
      end
    end
  end

  test "auth_method returns sso when set" do
    original_env = ENV["AUTH_METHOD"]
    begin
      ENV["AUTH_METHOD"] = "sso"
      assert_equal "sso", @account.auth_method
      assert @account.sso_auth?
      assert_not @account.password_auth?
      assert_not @account.otp_auth?
    ensure
      if original_env.nil?
        ENV.delete("AUTH_METHOD")
      else
        ENV["AUTH_METHOD"] = original_env
      end
    end
  end

  test "auth_method falls back to password for invalid ENV value" do
    original_env = ENV["AUTH_METHOD"]
    begin
      ENV["AUTH_METHOD"] = "invalid"
      assert_equal "password", @account.auth_method
      assert @account.password_auth?
    ensure
      if original_env.nil?
        ENV.delete("AUTH_METHOD")
      else
        ENV["AUTH_METHOD"] = original_env
      end
    end
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

  test "rejects SVG logo uploads" do
    assert_raises(Account::InvalidLogoType) do
      @account.attach_logo({ io: file_fixture("logo.svg").open, filename: "logo.svg", content_type: "image/svg+xml" })
    end
    assert_not @account.logo.attached?
  end

  test "accepts JPEG logo uploads" do
    @account.attach_logo({ io: file_fixture("moon.jpg").open, filename: "moon.jpg", content_type: "image/jpeg" })
    assert @account.logo.attached?
  end

  test "email flags are queryable as boolean columns, not JSON extraction" do
    @account.update!(email_notifications_enabled: true, weekly_digest_enabled: true)

    found = Account.where(email_notifications_enabled: true, weekly_digest_enabled: true).first
    assert_equal @account.id, found.id
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
