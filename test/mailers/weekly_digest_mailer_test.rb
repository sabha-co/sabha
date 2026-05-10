require "test_helper"

class WeeklyDigestMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:jason)
    @user.notification_settings || @user.create_notification_settings!
    @actor = users(:david)
    @room  = rooms(:designers)

    @everyone_message = @room.messages.create!(
      body: "<div>heads up #{mention_attachment_for(:jason)}</div>",
      creator: @actor,
      client_message_id: "digest_mailer_msg",
      mentions_everyone: true
    )

    @content = Struct.new(:everyone_mentions, :active_rooms, :excerpts).new(
      [ @everyone_message ],
      [ [ @room, 7 ] ],
      [ @everyone_message ]
    )
  end

  test "subject is workspace-recap framed (no sender, no room)" do
    mail = WeeklyDigestMailer.digest(@user, @content)

    assert_match(/^This week in /, mail.subject)
    assert_no_match(/#{@actor.name}/, mail.subject)
    assert_no_match(/#{@room.name}/, mail.subject)
  end

  test "renders multipart with text and html" do
    mail = WeeklyDigestMailer.digest(@user, @content)

    assert_equal 2, mail.parts.size
    assert mail.parts.any? { |p| p.content_type.include?("text/plain") }
    assert mail.parts.any? { |p| p.content_type.include?("text/html") }
  end

  test "RFC 8058 List-Unsubscribe headers point at the unsubscribe URL" do
    mail = WeeklyDigestMailer.digest(@user, @content)

    list_unsub_value = mail.header["List-Unsubscribe"]&.value
    assert_match(/<https?:\/\/[^>]+\/email\/unsubscribe\/.+>/, list_unsub_value)
    assert_equal "List-Unsubscribe=One-Click", mail.header["List-Unsubscribe-Post"]&.value
  end

  test "unsubscribe token resolves to the weekly_digest surface" do
    mail = WeeklyDigestMailer.digest(@user, @content)

    list_unsub_value = mail.header["List-Unsubscribe"]&.value
    token = list_unsub_value[/email\/unsubscribe\/([^>]+)/, 1]
    payload = Rails.application.message_verifier(:email_unsubscribe).verify(token).symbolize_keys

    assert_equal @user.id, payload[:user_id]
    assert_equal "weekly_digest", payload[:surface].to_s
  end

  test "delivers to the user" do
    mail = WeeklyDigestMailer.digest(@user, @content)

    assert_equal [ @user.email_address ], mail.to
  end

  test "body includes room names and excerpts" do
    mail = WeeklyDigestMailer.digest(@user, @content)

    body = mail.html_part.body.to_s
    assert_includes body, @room.name
    assert_includes body, @actor.name
  end
end
