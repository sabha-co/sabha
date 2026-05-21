# Renders the weekly activity digest. Trusts the caller's selection rules —
# does not re-validate. Independent unsubscribe scope from missed-notification
# mail: clicking unsubscribe here only flips weekly_digest_subscribed.
class WeeklyDigestMailer < ApplicationMailer
  include EmailUnsubscribable

  PREVIEW_TRUNCATION = 140

  helper do
    def preview_for(message)
      message.plain_text_body.to_s.truncate(WeeklyDigestMailer::PREVIEW_TRUNCATION)
    end

    def sender_for(message)
      message.creator&.name.presence || "Someone"
    end
  end

  def digest(user, content)
    @user              = user
    @content           = content
    @workspace_name    = workspace_name
    @everyone_mentions = content.everyone_mentions
    @active_rooms      = content.active_rooms
    @excerpts          = content.excerpts
    @activity_url      = inbox_activity_index_url(script_name: tenant_script_name)
    @settings_url      = edit_user_notification_settings_url(user_id: "me", script_name: tenant_script_name)
    @unsubscribe_url   = unsubscribe_url_for(@user, :weekly_digest)

    unsubscribe_headers(@user, :weekly_digest).each { |key, value| headers[key] = value }

    mail to: @user.email_address, subject: "This week in #{@workspace_name}"
  end
end
