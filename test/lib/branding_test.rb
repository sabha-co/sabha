# frozen_string_literal: true

require "test_helper"

class BrandingTest < ActiveSupport::TestCase
  # Self-hosted mode (default in test environment)

  test "mailer_from formats name and email in self-hosted mode" do
    expected = "#{Rails.configuration.x.branding.mailer_from_name} <#{Rails.configuration.x.branding.mailer_from_email}>"
    assert_equal expected, Branding.mailer_from
  end

  test "contextual_app_name returns app_name in self-hosted mode" do
    assert_equal Branding.app_name, Branding.contextual_app_name
  end

  test "app_url uses http in test environment" do
    assert_equal "http://#{Branding.app_host}", Branding.app_url
  end

  # SaaS mode

  test "app_name returns hardcoded value in SaaS mode" do
    stub_saas do
      assert_equal "Sabha", Branding.app_name
    end
  end

  test "support_email defaults to hardcoded value in SaaS mode" do
    stub_saas do
      stub_env("SUPPORT_EMAIL", nil) do
        assert_equal "ashwin@sabha.co", Branding.support_email
      end
    end
  end

  test "support_email respects ENV override in SaaS mode" do
    stub_saas do
      stub_env("SUPPORT_EMAIL", "staging@example.com") do
        assert_equal "staging@example.com", Branding.support_email
      end
    end
  end

  test "app_host defaults to hardcoded value in SaaS mode" do
    stub_saas do
      stub_env("APP_HOST", nil) do
        assert_equal "sabha.co", Branding.app_host
      end
    end
  end

  test "app_host respects ENV override in SaaS mode" do
    stub_saas do
      stub_env("APP_HOST", "staging.sabha.co") do
        assert_equal "staging.sabha.co", Branding.app_host
      end
    end
  end

  test "mailer_from defaults to hardcoded sender in SaaS mode" do
    stub_saas do
      stub_env("MAILER_FROM_NAME", nil) do
        stub_env("MAILER_FROM_EMAIL", nil) do
          assert_equal "Sabha <ashwin@sabha.co>", Branding.mailer_from
        end
      end
    end
  end

  test "mailer_from respects ENV override in SaaS mode" do
    stub_saas do
      stub_env("MAILER_FROM_NAME", "Staging") do
        stub_env("MAILER_FROM_EMAIL", "noreply@staging.sabha.co") do
          assert_equal "Staging <noreply@staging.sabha.co>", Branding.mailer_from
        end
      end
    end
  end

  test "contextual_app_name returns Sabha when no workspace in SaaS mode" do
    stub_saas do
      Current.stubs(:workspace).returns(nil)
      assert_equal "Sabha", Branding.contextual_app_name
    end
  end

  test "contextual_app_name returns workspace name when present in SaaS mode" do
    stub_saas do
      workspace = Data.define(:name).new(name: "My Community")
      Current.stubs(:workspace).returns(workspace)
      assert_equal "My Community", Branding.contextual_app_name
    end
  end

  private

  def stub_saas
    Sabha.stubs(:saas?).returns(true)
    yield
  ensure
    Sabha.unstub(:saas?)
  end

  def stub_env(key, value)
    old = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    old.nil? ? ENV.delete(key) : ENV[key] = old
  end
end
