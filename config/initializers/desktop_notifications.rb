Rails.application.config.x.desktop_notifications_enabled =
  ENV.fetch("DESKTOP_NOTIFICATIONS_ENABLED", "true") == "true"
