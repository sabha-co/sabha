# frozen_string_literal: true

require "test_helper"

class BrandingTest < ActiveSupport::TestCase
  # Self-hosted mode (default in test environment)

  test "app_name returns ENV value in self-hosted mode" do
    assert_equal ENV.fetch("APP_NAME", "Sabha"), Branding.app_name
  end

  test "support_email returns ENV value in self-hosted mode" do
    assert_equal ENV.fetch("SUPPORT_EMAIL", "support@example.com"), Branding.support_email
  end

  test "app_host returns ENV value in self-hosted mode" do
    assert_equal ENV.fetch("APP_HOST", "localhost"), Branding.app_host
  end

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

  test "support_email returns hardcoded value in SaaS mode" do
    stub_saas do
      assert_equal "ashwin@sabha.co", Branding.support_email
    end
  end

  test "app_host returns hardcoded value in SaaS mode" do
    stub_saas do
      assert_equal "sabha.co", Branding.app_host
    end
  end

  test "mailer_from returns hardcoded sender in SaaS mode" do
    stub_saas do
      assert_equal "Sabha <ashwin@sabha.co>", Branding.mailer_from
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

  test "SAAS constant is frozen" do
    assert Branding::SAAS.frozen?
  end

  private

  def stub_saas
    Sabha.stubs(:saas?).returns(true)
    yield
  ensure
    Sabha.unstub(:saas?)
  end
end
