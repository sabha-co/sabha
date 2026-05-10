require "test_helper"

class EmailUnsubscribableTest < ActiveSupport::TestCase
  class FakeMailer
    include EmailUnsubscribable

    def email_unsubscribe_url(token:)
      "https://example.com/email/unsubscribe/#{token}"
    end

    def call(*args)
      send(*args)
    end
  end

  setup do
    @user = users(:david)
    @mailer = FakeMailer.new
  end

  test "mint_unsubscribe_token round-trips through the verifier" do
    token   = @mailer.call(:mint_unsubscribe_token, @user, :missed_notifications)
    payload = Rails.application.message_verifier(:email_unsubscribe).verify(token).symbolize_keys

    assert_equal @user.id, payload[:user_id]
    assert_equal "missed_notifications", payload[:surface].to_s
  end

  test "mint_unsubscribe_token rejects unknown surfaces" do
    assert_raises(ArgumentError) do
      @mailer.call(:mint_unsubscribe_token, @user, :marketing)
    end
  end

  test "mint_unsubscribe_token records nil tenant in self-hosted" do
    skip "SaaS-only" if Sabha.saas?

    token   = @mailer.call(:mint_unsubscribe_token, @user, :weekly_digest)
    payload = Rails.application.message_verifier(:email_unsubscribe).verify(token).symbolize_keys

    assert_nil payload[:tenant], "self-hosted token should encode tenant=nil"
  end

  test "tampered token fails verification" do
    token = @mailer.call(:mint_unsubscribe_token, @user, :missed_notifications)
    tampered = token.split(".").tap { |parts| parts[0] = parts[0].reverse }.join(".")

    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
      Rails.application.message_verifier(:email_unsubscribe).verify(tampered)
    end
  end

  test "unsubscribe_headers includes RFC 8058 List-Unsubscribe and List-Unsubscribe-Post" do
    headers = @mailer.call(:unsubscribe_headers, @user, :missed_notifications)

    assert_match(/\Ahttps:\/\/example.com\/email\/unsubscribe\/.+/, headers["List-Unsubscribe"][1..-2])
    assert_equal "List-Unsubscribe=One-Click", headers["List-Unsubscribe-Post"]
  end

  test "workspace_name falls back to Branding when Account.sole is missing" do
    Account.stubs(:sole).returns(nil)
    assert_equal Branding.contextual_app_name, @mailer.call(:workspace_name)
  end
end
