require "test_helper"

class MissedNotificationsMailerTest < ActionMailer::TestCase
  setup do
    @user  = users(:jason)
    @actor = users(:david)
    @room  = rooms(:designers)

    @bundle = Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: Time.current, ends_at: 1.hour.from_now
    )
    @message = @room.messages.create!(
      body: "<div>hello #{mention_attachment_for(:jason)}</div>",
      creator: @actor,
      client_message_id: "mailer_test_msg"
    )
    @item = Notification::BundleItem.create!(bundle: @bundle, message: @message, actor: @actor, kind: "mention")
  end

  test "subject is generic — workspace name, no sender or room" do
    mail = MissedNotificationsMailer.bundle(@bundle, [ @item ])

    assert_match(/New mentions in/, mail.subject)
    assert_no_match(/#{@actor.name}/, mail.subject)
    assert_no_match(/#{@room.name}/, mail.subject)
  end

  test "subject reflects DM-only bundles" do
    @item.update!(kind: "direct_message")
    mail = MissedNotificationsMailer.bundle(@bundle, [ @item ])

    assert_match(/new messages/i, mail.subject)
    assert_no_match(/mentions/i, mail.subject)
  end

  test "body lists sender + preview + room label" do
    mail = MissedNotificationsMailer.bundle(@bundle, [ @item ])

    body = mail.html_part.body.to_s
    assert_includes body, @actor.name
    assert_includes body, @room.name
    assert_includes body, "Open Activity"
  end

  test "header X-Idempotency-Key is stable across the bundle" do
    mail = MissedNotificationsMailer.bundle(@bundle, [ @item ])

    assert_equal "bundle-#{@bundle.id}", mail.header["X-Idempotency-Key"]&.value
  end

  test "RFC 8058 List-Unsubscribe headers point at the unsubscribe URL" do
    mail = MissedNotificationsMailer.bundle(@bundle, [ @item ])

    list_unsub_value = mail.header["List-Unsubscribe"]&.value
    assert_match(/<https?:\/\/[^>]+\/email\/unsubscribe\/.+>/, list_unsub_value)
    assert_equal "List-Unsubscribe=One-Click", mail.header["List-Unsubscribe-Post"]&.value
  end

  test "unsubscribe token resolves to the missed_notifications surface" do
    mail = MissedNotificationsMailer.bundle(@bundle, [ @item ])

    list_unsub_value = mail.header["List-Unsubscribe"]&.value
    token = list_unsub_value[/email\/unsubscribe\/([^>]+)/, 1]
    payload = Rails.application.message_verifier(:email_unsubscribe).verify(token).symbolize_keys

    assert_equal @user.id, payload[:user_id]
    assert_equal "missed_notifications", payload[:surface].to_s
  end

  test "delivers to the bundle owner" do
    mail = MissedNotificationsMailer.bundle(@bundle, [ @item ])

    assert_equal [ @user.email_address ], mail.to
  end
end
