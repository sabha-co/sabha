require "test_helper"

class BootModeTest < ActiveSupport::TestCase
  test "SaaS mode aborts when configured for SSO auth" do
    original_auth_method = ENV["AUTH_METHOD"]
    ENV["AUTH_METHOD"] = "sso"
    Sabha.stubs(:saas?).returns(true)

    error = nil
    _stdout, stderr = capture_io do
      error = assert_raises SystemExit do
        load Rails.root.join("config/initializers/00_boot_mode.rb")
      end
    end

    assert_equal 1, error.status
    assert_match /AUTH_METHOD=sso/, stderr
  ensure
    Sabha.unstub(:saas?)
    original_auth_method.nil? ? ENV.delete("AUTH_METHOD") : ENV["AUTH_METHOD"] = original_auth_method
  end
end
