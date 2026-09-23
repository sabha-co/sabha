# Read through Desktop.notifications_enabled?. The test environment turns it
# on so the delivery path stays covered.
if Rails.application.config.x.desktop_notifications_enabled.nil?
  Rails.application.config.x.desktop_notifications_enabled =
    ENV.fetch("DESKTOP_NOTIFICATIONS_ENABLED", "false") == "true"
end
