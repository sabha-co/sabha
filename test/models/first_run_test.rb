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

  private
    def create_first_run_user
      FirstRun.create!({ name: "User", email_address: "user@example.com", password: "secret123456" })
    end
end

class FirstRunAutoBootstrapTest < ActiveSupport::TestCase
  # AutoBootstrap is for Campfire Cloud only (uses ADMIN_AUTH_TOKEN)
  # For Kamal/self-hosted: use the manual first_run flow

  VALID_TEST_TOKEN = "test-token-abc123-secure-random-value-here"

  setup do
    Account.destroy_all
    User.destroy_all
    Room.destroy_all

    @original_env = {
      "AUTO_BOOTSTRAP" => ENV["AUTO_BOOTSTRAP"],
      "ADMIN_EMAIL" => ENV["ADMIN_EMAIL"],
      "ADMIN_AUTH_TOKEN" => ENV["ADMIN_AUTH_TOKEN"],
      "ADMIN_NAME" => ENV["ADMIN_NAME"]
    }

    @original_env.keys.each { |key| ENV.delete(key) }
  end

  teardown do
    @original_env.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  test "auto_bootstrap_enabled? returns true when all required env vars are set" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    assert FirstRun.auto_bootstrap_enabled?
  end

  test "auto_bootstrap_enabled? returns false when AUTO_BOOTSTRAP is not true" do
    ENV["AUTO_BOOTSTRAP"] = "false"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    assert_not FirstRun.auto_bootstrap_enabled?
  end

  test "auto_bootstrap_enabled? returns false when ADMIN_EMAIL is missing" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    assert_not FirstRun.auto_bootstrap_enabled?
  end

  test "auto_bootstrap_enabled? returns false when ADMIN_AUTH_TOKEN is missing" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"

    assert_not FirstRun.auto_bootstrap_enabled?
  end

  test "should_auto_bootstrap? returns true when enabled and no account exists" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    assert FirstRun.should_auto_bootstrap?
  end

  test "should_auto_bootstrap? returns false when account already exists" do
    Account.create!(name: "Test")

    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    assert_not FirstRun.should_auto_bootstrap?
  end

  test "auto_bootstrap! creates admin user with correct attributes" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN
    ENV["ADMIN_NAME"] = "Test Admin"

    admin = FirstRun.auto_bootstrap!

    assert admin.persisted?
    assert_equal "admin@example.com", admin.email_address
    assert_equal "Test Admin", admin.name
    assert admin.administrator?
  end

  test "auto_bootstrap! creates auth token for first login" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    admin = FirstRun.auto_bootstrap!

    auth_token = admin.auth_tokens.find_by(token: VALID_TEST_TOKEN)
    assert auth_token.present?
    assert auth_token.expires_at > Time.current
    assert auth_token.expires_at <= 24.hours.from_now
  end

  test "auto_bootstrap! pre-verifies the user email" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    admin = FirstRun.auto_bootstrap!

    assert admin.verified?
  end

  test "auto_bootstrap! creates account and initial room" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    assert_difference "Account.count", 1 do
      assert_difference "Room.count", 1 do
        FirstRun.auto_bootstrap!
      end
    end
  end

  test "auto_bootstrap! uses default name when ADMIN_NAME not provided" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    admin = FirstRun.auto_bootstrap!

    assert_equal "Administrator", admin.name
  end

  test "auto_bootstrap! returns false when should not run" do
    Account.create!(name: "Test")

    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = VALID_TEST_TOKEN

    result = FirstRun.auto_bootstrap!

    assert_equal false, result
  end

  test "auto_bootstrap! raises error if ADMIN_AUTH_TOKEN is too short" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_AUTH_TOKEN"] = "short-token"

    assert_raises(ArgumentError) do
      FirstRun.auto_bootstrap!
    end
  end
end
