require "test_helper"
require "mail"
require "mocha/minitest"

class ResendDeliveryMethodTest < ActiveSupport::TestCase
  test "raises when API key is missing" do
    dm = ResendDeliveryMethod.new({})
    mail = Mail.new(from: "noreply@sabha.co", to: "user@example.com", subject: "Test", body: "Hello")

    original = ENV["RESEND_API_KEY"]
    ENV["RESEND_API_KEY"] = nil

    assert_raises(ArgumentError) { dm.deliver!(mail) }
  ensure
    ENV["RESEND_API_KEY"] = original
  end

  test "delivers plain text email" do
    dm = ResendDeliveryMethod.new(api_key: "re_test")
    mail = Mail.new(from: "noreply@sabha.co", to: "user@example.com", subject: "Test", body: "Hello")

    Resend::Emails.expects(:send).once.with do |params|
      params[:from] == "noreply@sabha.co" &&
        params[:to] == [ "user@example.com" ] &&
        params[:subject] == "Test" &&
        params[:text] == "Hello"
    end

    dm.deliver!(mail)
  end

  test "delivers multipart email with text and html" do
    dm = ResendDeliveryMethod.new(api_key: "re_test")
    mail = Mail.new do
      from    "noreply@sabha.co"
      to      "user@example.com"
      subject "Test"

      text_part { body "Plain text" }
      html_part do
        content_type "text/html; charset=UTF-8"
        body "<h1>HTML</h1>"
      end
    end

    Resend::Emails.expects(:send).once.with do |params|
      params[:text] == "Plain text" && params[:html] == "<h1>HTML</h1>"
    end

    dm.deliver!(mail)
  end

  test "prefers API key from settings over env" do
    dm = ResendDeliveryMethod.new(api_key: "re_from_settings")

    Resend::Emails.expects(:send).once
    dm.deliver!(Mail.new(from: "a@b.co", to: "c@d.co", subject: "X", body: "Y"))

    assert_equal "re_from_settings", Resend.api_key
  end

  test "passes X-Idempotency-Key header through as Resend's idempotency_key param" do
    dm = ResendDeliveryMethod.new(api_key: "re_test")
    mail = Mail.new(from: "a@b.co", to: "c@d.co", subject: "X", body: "Y")
    mail.header["X-Idempotency-Key"] = "bundle-42"

    Resend::Emails.expects(:send).once.with do |params|
      params[:idempotency_key] == "bundle-42"
    end

    dm.deliver!(mail)
  end

  test "forwards List-Unsubscribe headers via Resend's headers param" do
    dm = ResendDeliveryMethod.new(api_key: "re_test")
    mail = Mail.new(from: "a@b.co", to: "c@d.co", subject: "X", body: "Y")
    mail.header["List-Unsubscribe"] = "<https://example.com/u/abc>"
    mail.header["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    Resend::Emails.expects(:send).once.with do |params|
      params[:headers]["List-Unsubscribe"] == "<https://example.com/u/abc>" &&
        params[:headers]["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
    end

    dm.deliver!(mail)
  end

  test "omits idempotency_key when no header is present" do
    dm = ResendDeliveryMethod.new(api_key: "re_test")
    mail = Mail.new(from: "a@b.co", to: "c@d.co", subject: "X", body: "Y")

    Resend::Emails.expects(:send).once.with do |params|
      !params.key?(:idempotency_key)
    end

    dm.deliver!(mail)
  end
end

class SesDeliveryMethodTest < ActiveSupport::TestCase
  setup do
    @dm = SesDeliveryMethod.new({})
    @mail = Mail.new(from: "noreply@sabha.co", to: "user@example.com", subject: "Test", body: "Hello")
  end

  test "configuration_set defaults to sabha-ses" do
    original = ENV["SES_CONFIGURATION_SET"]
    ENV.delete("SES_CONFIGURATION_SET")

    assert_equal "sabha-ses", @dm.send(:configuration_set_for, @mail)
  ensure
    ENV["SES_CONFIGURATION_SET"] = original if original
  end

  test "configuration_set reads from env" do
    original = ENV["SES_CONFIGURATION_SET"]
    ENV["SES_CONFIGURATION_SET"] = "custom-set"

    assert_equal "custom-set", @dm.send(:configuration_set_for, @mail)
  ensure
    ENV["SES_CONFIGURATION_SET"] = original
  end

  test "configuration_set prefers mail header over env" do
    @mail.header["X-SES-CONFIGURATION-SET"] = "header-set"

    original = ENV["SES_CONFIGURATION_SET"]
    ENV["SES_CONFIGURATION_SET"] = "env-set"

    assert_equal "header-set", @dm.send(:configuration_set_for, @mail)
  ensure
    ENV["SES_CONFIGURATION_SET"] = original
  end

  test "raises without aws-sdk-sesv2 gem" do
    skip "gem is available in this environment" if SES_AVAILABLE

    assert_raises(RuntimeError) { @dm.deliver!(@mail) }
  end
end
