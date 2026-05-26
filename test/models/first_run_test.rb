require "test_helper"

class FirstRunTest < ActiveSupport::TestCase
  setup do
    Account.destroy_all
    Room.destroy_all
    User.destroy_all
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

  test "first room is auto_join so new signups land directly in it" do
    create_first_run_user
    assert Room.first.auto_join?
  end

  private
    def create_first_run_user
      FirstRun.create!({ name: "User", email_address: "user@example.com", password: "secret123456" })
    end
end

class FirstRunAutoBootstrapFromSsoTest < ActiveSupport::TestCase
  setup do
    Account.destroy_all
    Room.destroy_all
    User.destroy_all
  end

  test "creates account, administrator, sso record, and auto-join General room" do
    admin = FirstRun.auto_bootstrap_from_sso!(payload)

    assert_equal 1, Account.count
    assert admin.administrator?
    assert admin.verified?
    assert_equal "first-admin@example.com", admin.email_address
    assert_equal "First Admin", admin.name
    assert_equal "ext-first-admin", admin.single_sign_on_record.external_id

    general = Room.first
    assert_equal "General", general.name
    assert general.open?
    assert general.auto_join?
    assert_includes admin.rooms, general
  end

  test "returns false when an account already exists" do
    Account.create!(name: "Existing")

    assert_equal false, FirstRun.auto_bootstrap_from_sso!(payload)
  end

  private
    def payload
      {
        "external_id" => "ext-first-admin",
        "email" => "first-admin@example.com",
        "name" => "First Admin"
      }
    end
end

class FirstRunSsoBootstrapEnabledTest < ActiveSupport::TestCase
  setup do
    @original_env = {
      "AUTO_BOOTSTRAP" => ENV["AUTO_BOOTSTRAP"],
      "SSO_PROVIDER_URL" => ENV["SSO_PROVIDER_URL"],
      "SSO_SECRET" => ENV["SSO_SECRET"]
    }
    @original_env.keys.each { |key| ENV.delete(key) }
  end

  teardown do
    @original_env.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  test "auto_bootstrap_enabled? requires AUTO_BOOTSTRAP plus SSO provider config" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["SSO_PROVIDER_URL"] = "https://sabha.co/session/sso"
    ENV["SSO_SECRET"] = "test-secret"

    assert FirstRun.auto_bootstrap_enabled?
  end

  test "auto_bootstrap_enabled? is false when SSO provider env is missing" do
    ENV["AUTO_BOOTSTRAP"] = "true"

    assert_not FirstRun.auto_bootstrap_enabled?
  end

  test "auto_bootstrap_enabled? is false when AUTO_BOOTSTRAP is not true" do
    ENV["AUTO_BOOTSTRAP"] = "false"
    ENV["SSO_PROVIDER_URL"] = "https://sabha.co/session/sso"
    ENV["SSO_SECRET"] = "test-secret"

    assert_not FirstRun.auto_bootstrap_enabled?
  end

  test "should_auto_bootstrap? is false once an account exists" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["SSO_PROVIDER_URL"] = "https://sabha.co/session/sso"
    ENV["SSO_SECRET"] = "test-secret"

    assert_not FirstRun.should_auto_bootstrap?, "should be false because fixtures already created an Account"
  end
end
