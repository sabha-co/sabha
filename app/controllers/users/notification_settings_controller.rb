# Per-user notification preferences. Always operates on the current user;
# the :user_id route param is hard-coded to "me" so URLs are stable across
# views (matching push_subscriptions, profile, etc.).
class Users::NotificationSettingsController < ApplicationController
  before_action :set_settings

  def edit
  end

  def update
    @settings.update!(notification_settings_params)
    redirect_to edit_user_notification_settings_path(user_id: "me"), notice: "Notification preferences saved."
  end

  private
    def set_settings
      @settings = Current.user.notification_settings || Current.user.create_notification_settings!
    end

    def notification_settings_params
      params.require(:user_notification_settings).permit(
        :missed_email_enabled,
        :email_frequency,
        :weekly_digest_subscribed,
        :push_enabled
      )
    end
end
