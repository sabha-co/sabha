require "test_helper"

class AutoBootstrapTest < ActiveSupport::TestCase
  setup do
    Account.destroy_all
    User.destroy_all
    Room.destroy_all

    # Capture original env values before tests modify them
    @original_env = {
      "AUTO_BOOTSTRAP" => ENV["AUTO_BOOTSTRAP"],
      "ADMIN_EMAIL" => ENV["ADMIN_EMAIL"],
      "ADMIN_PASSWORD" => ENV["ADMIN_PASSWORD"],
      "ADMIN_NAME" => ENV["ADMIN_NAME"]
    }

    # Clear env vars for clean test state
    @original_env.keys.each { |key| ENV.delete(key) }
  end

  teardown do
    # Restore original env values
    @original_env.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  test "enabled? returns true when all required env vars are set" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    assert AutoBootstrap.enabled?
  end

  test "enabled? returns false when AUTO_BOOTSTRAP is not true" do
    ENV["AUTO_BOOTSTRAP"] = "false"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    assert_not AutoBootstrap.enabled?
  end

  test "enabled? returns false when ADMIN_EMAIL is missing" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    assert_not AutoBootstrap.enabled?
  end

  test "enabled? returns false when ADMIN_PASSWORD is missing" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"

    assert_not AutoBootstrap.enabled?
  end

  test "should_run? returns true when enabled and no account exists" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    assert AutoBootstrap.should_run?
  end

  test "should_run? returns false when account already exists" do
    Account.create!(name: "Test")

    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    assert_not AutoBootstrap.should_run?
  end

  test "run! creates admin user with correct attributes" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"
    ENV["ADMIN_NAME"] = "Test Admin"

    admin = AutoBootstrap.run!

    assert admin.persisted?
    assert_equal "admin@example.com", admin.email_address
    assert_equal "Test Admin", admin.name
    assert admin.administrator?
  end

  test "run! sets must_change_password flag to true" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    admin = AutoBootstrap.run!

    assert admin.must_change_password?
  end

  test "run! pre-verifies the user email" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    admin = AutoBootstrap.run!

    assert admin.verified?
  end

  test "run! creates account and initial room" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    assert_difference "Account.count", 1 do
      assert_difference "Room.count", 1 do
        AutoBootstrap.run!
      end
    end
  end

  test "run! uses default name when ADMIN_NAME not provided" do
    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    admin = AutoBootstrap.run!

    assert_equal "Administrator", admin.name
  end

  test "run! returns false when should not run" do
    Account.create!(name: "Test")

    ENV["AUTO_BOOTSTRAP"] = "true"
    ENV["ADMIN_EMAIL"] = "admin@example.com"
    ENV["ADMIN_PASSWORD"] = "testpass123"

    result = AutoBootstrap.run!

    assert_equal false, result
  end
end
