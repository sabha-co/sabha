# frozen_string_literal: true

require "test_helper"

class SabhaTest < ActiveSupport::TestCase
  test "email_configured? is false when EMAIL_GLOBALLY_DISABLED is set, regardless of mode or env" do
    with_env("EMAIL_GLOBALLY_DISABLED" => "true", "RESEND_API_KEY" => "rsnd_test") do
      assert_not Sabha.email_configured?, "kill switch must override the test-env default"

      with_rails_env("development") do
        assert_not Sabha.email_configured?, "kill switch must override the dev-env default"
      end

      with_rails_env("production") do
        assert_not Sabha.email_configured?, "kill switch must override an otherwise-valid prod config"
      end
    end
  end

  test "email_configured? ignores EMAIL_GLOBALLY_DISABLED when not exactly 'true'" do
    with_env("EMAIL_GLOBALLY_DISABLED" => "1") do
      assert Sabha.email_configured?, "only the literal string 'true' arms the kill switch"
    end

    with_env("EMAIL_GLOBALLY_DISABLED" => "false") do
      assert Sabha.email_configured?, "'false' must not arm the kill switch"
    end
  end

  test "email_configured? is true in development without a provider key" do
    with_env("EMAIL_PROVIDER" => nil, "RESEND_API_KEY" => nil) do
      with_rails_env("development") do
        assert Sabha.email_configured?, "dev should always be considered configured (letter_opener)"
      end
    end
  end

  test "email_configured? is true in test without a provider key" do
    with_env("EMAIL_PROVIDER" => nil, "RESEND_API_KEY" => nil) do
      assert Sabha.email_configured?, "test env should always be considered configured (:test delivery)"
    end
  end

  test "email_configured? in production with default resend requires RESEND_API_KEY" do
    skip "SaaS path always returns true" if Sabha.saas?

    with_env("EMAIL_PROVIDER" => nil, "RESEND_API_KEY" => nil) do
      with_rails_env("production") do
        assert_not Sabha.email_configured?, "missing RESEND_API_KEY in production should hide the feature"
      end
    end

    with_env("EMAIL_PROVIDER" => "resend", "RESEND_API_KEY" => "rsnd_test") do
      with_rails_env("production") do
        assert Sabha.email_configured?, "RESEND_API_KEY present in production should expose the feature"
      end
    end
  end

  test "email_configured? in production with EMAIL_PROVIDER=ses requires the aws-sdk-sesv2 gem" do
    skip "SaaS path always returns true" if Sabha.saas?

    with_env("EMAIL_PROVIDER" => "ses", "RESEND_API_KEY" => nil) do
      with_rails_env("production") do
        # The aws-sdk-sesv2 gem only ships in Gemfile.saas, so SES_AVAILABLE
        # reflects whether self-hosted boot actually has the SES path wired.
        # Whichever way the test environment loaded, email_configured? must
        # mirror SES_AVAILABLE — never claim configured when SES would raise.
        ses_available = defined?(SES_AVAILABLE) && SES_AVAILABLE
        assert_equal ses_available, Sabha.email_configured?,
          "email_configured? should match SES_AVAILABLE for EMAIL_PROVIDER=ses on self-hosted"
      end
    end
  end

  private
    def with_rails_env(name)
      Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new(name))
      yield
    ensure
      Rails.unstub(:env)
    end

    def with_env(values)
      previous = {}
      values.each do |key, value|
        previous[key] = ENV[key]
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
end
