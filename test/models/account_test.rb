require "test_helper"

class AccountTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:signal)
  end

  test "auth_method defaults to password when ENV not set" do
    with_env "AUTH_METHOD" => nil do
      assert_equal "password", Account.auth_method
      assert Account.password_auth?
      assert_not Account.otp_auth?
      assert_not Account.sso_auth?
    end
  end

  test "auth_method returns otp when set" do
    with_env "AUTH_METHOD" => "otp" do
      assert_equal "otp", Account.auth_method
      assert Account.otp_auth?
      assert_not Account.password_auth?
      assert_not Account.sso_auth?
    end
  end

  test "auth_method returns sso when set" do
    with_env "AUTH_METHOD" => "sso" do
      assert_equal "sso", Account.auth_method
      assert Account.sso_auth?
      assert_not Account.password_auth?
      assert_not Account.otp_auth?
    end
  end

  test "auth_method falls back to password for invalid ENV value" do
    with_env "AUTH_METHOD" => "invalid" do
      assert_equal "password", Account.auth_method
      assert Account.password_auth?
    end
  end

  private
    def with_env(values)
      originals = values.transform_values { |_| nil }
      values.each_key { |key| originals[key] = ENV[key] }
      values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
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
    @account.logo.attach(io: file_fixture("logo.svg").open, filename: "logo.svg", content_type: "image/svg+xml")

    assert_not @account.valid?
    assert_includes @account.errors[:logo], "must be a JPEG, PNG, GIF, or WebP image"
  end

  test "rejects oversize logo uploads" do
    @account.logo.attach(io: StringIO.new("x" * (Account::MAX_LOGO_SIZE + 1)), filename: "huge.png", content_type: "image/png")

    assert_not @account.valid?
    assert_includes @account.errors[:logo], "is too large (max #{Account::MAX_LOGO_SIZE / 1.megabyte}MB)"
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
