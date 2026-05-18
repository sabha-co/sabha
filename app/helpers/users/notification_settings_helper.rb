module Users::NotificationSettingsHelper
  def email_section_visible?
    missed_email_section_visible? || weekly_digest_section_visible?
  end

  def missed_email_section_visible?
    Current.account.email_notifications_enabled? || Current.user.administrator?
  end

  def weekly_digest_section_visible?
    Current.account.weekly_digest_enabled? || Current.user.administrator?
  end

  def all_email_features_disabled?
    !Current.account.email_notifications_enabled? && !Current.account.weekly_digest_enabled?
  end
end
