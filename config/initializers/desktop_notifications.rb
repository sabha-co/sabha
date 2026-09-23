# Off until the desktop app ships: every eligible recipient otherwise costs a
# badge query and a broadcast per message, whether or not they run the app.
# The test environment turns it on so the delivery path stays covered.
if Rails.application.config.x.desktop_notifications_enabled.nil?
  Rails.application.config.x.desktop_notifications_enabled =
    ENV.fetch("DESKTOP_NOTIFICATIONS_ENABLED", "false") == "true"
end
