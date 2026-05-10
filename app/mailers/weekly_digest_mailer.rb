# Renders the weekly activity digest handed to it by Notification::WeeklyDigestJob.
# Independent unsubscribe scope from missed-notification mail (R10) — token surface
# is :weekly_digest. The mailer trusts the job's selection rules; it does not
# re-check eligibility.
#
# See docs/plans/NOTIFICATIONS-ARCHITECTURE.md § 8.3, § 8.4.
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
    @user            = user
    @workspace_name  = workspace_name
    @everyone_mentions = content[:everyone_mentions]
    @active_rooms      = content[:active_rooms]
    @excerpts          = content[:excerpts]
    @activity_url    = activity_inbox_url
    @settings_url    = edit_user_notification_settings_url(user_id: "me")
    @unsubscribe_url = unsubscribe_url_for(@user, :weekly_digest)

    unsubscribe_headers(@user, :weekly_digest).each { |key, value| headers[key] = value }

    mail to: @user.email_address, subject: "This week in #{@workspace_name}"
  end
end
