# Renders the bundled missed-notification email. Trusts the caller's
# eligibility check — does not re-validate. Emits a stable idempotency key so
# Solid Queue retries dedup at the provider rather than the DB.
#
# Subject stays generic (workspace + activity-type only) for inbox privacy;
# sender and room names live in the body.
class MissedNotificationsMailer < ApplicationMailer
  include EmailUnsubscribable

  PREVIEW_TRUNCATION = 140

  helper do
    def preview_for(item)
      item.message.plain_text_body.to_s.truncate(MissedNotificationsMailer::PREVIEW_TRUNCATION)
    end

    def sender_for(item)
      item.actor&.name.presence || "Someone"
    end

    def room_label_for(room)
      case room
      when Rooms::Direct then "Direct message"
      when Rooms::Thread then "Thread in #{room.parent_room&.name || "a room"}"
      else room.name
      end
    end
  end

  def bundle(bundle, items)
    @bundle          = bundle
    @user            = bundle.user
    @items           = items
    @workspace_name  = workspace_name
    @grouped_items   = items.group_by { |item| item.message.room }
    @activity_url    = inbox_activity_index_url(script_name: tenant_script_name)
    @settings_url    = edit_user_notification_settings_url(user_id: "me", script_name: tenant_script_name)
    @unsubscribe_url = unsubscribe_url_for(@user, :missed_notifications)

    headers["X-Idempotency-Key"] = "bundle-#{bundle.id}"
    unsubscribe_headers(@user, :missed_notifications).each { |key, value| headers[key] = value }

    mail to: @user.email_address, subject: subject_for(items)
  end

  private
    def subject_for(items)
      if items.any? { |item| item.kind == "mention" }
        "New mentions in #{@workspace_name}"
      else
        "You have new messages in #{@workspace_name}"
      end
    end
end
