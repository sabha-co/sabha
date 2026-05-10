require "test_helper"

class EmailUnsubscribesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:david)
    settings = @user.notification_settings || @user.create_notification_settings!
    settings.update!(missed_email_enabled: true, weekly_digest_subscribed: true)
  end

  test "POST one-click flips missed_email_enabled to false" do
    token = mint_token(:missed_notifications)

    post email_unsubscribe_url(token: token)

    assert_response :success
    refute @user.reload.notification_settings.missed_email_enabled
  end

  test "POST one-click on weekly_digest surface flips weekly_digest_subscribed only" do
    token = mint_token(:weekly_digest)

    post email_unsubscribe_url(token: token)

    assert_response :success
    refute @user.reload.notification_settings.weekly_digest_subscribed
    assert @user.notification_settings.missed_email_enabled,
      "weekly digest unsubscribe must not affect missed-notification preference (R10)"
  end

  test "GET shows the confirmation page" do
    token = mint_token(:missed_notifications)

    get email_unsubscribe_url(token: token)

    assert_response :success
    assert_select "form[action=?]", email_unsubscribe_path(token: token)
  end

  test "re-clicking is idempotent" do
    token = mint_token(:missed_notifications)
    @user.notification_settings.update!(missed_email_enabled: false)

    post email_unsubscribe_url(token: token)

    assert_response :success
    refute @user.reload.notification_settings.missed_email_enabled
  end

  test "tampered token renders the invalid page with 404" do
    token = mint_token(:missed_notifications)
    tampered = token.split(".").tap { |parts| parts[0] = parts[0].reverse }.join(".")

    post email_unsubscribe_url(token: tampered)

    assert_response :not_found
    assert @user.reload.notification_settings.missed_email_enabled,
      "no setting may flip when the signature is invalid"
  end

  test "unknown surface in payload renders invalid" do
    payload = { user_id: @user.id, tenant: nil, surface: :marketing }
    token = Rails.application.message_verifier(:email_unsubscribe).generate(payload)

    post email_unsubscribe_url(token: token)

    assert_response :not_found
  end

  test "unknown user_id is a no-op success" do
    payload = { user_id: -1, tenant: nil, surface: :missed_notifications }
    token = Rails.application.message_verifier(:email_unsubscribe).generate(payload)

    post email_unsubscribe_url(token: token)

    assert_response :success
    assert @user.reload.notification_settings.missed_email_enabled
  end

  test "skips CSRF protection on POST" do
    ActionController::Base.allow_forgery_protection = true
    token = mint_token(:missed_notifications)

    post email_unsubscribe_url(token: token)

    assert_response :success
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  private
    def mint_token(surface)
      payload = { user_id: @user.id, tenant: nil, surface: surface }
      Rails.application.message_verifier(:email_unsubscribe).generate(payload)
    end
end
