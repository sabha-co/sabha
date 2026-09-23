module Desktop
  PROTOCOL_MAJOR = 1

  UPGRADE_URL = "https://github.com/sabha-co/sabha-desktop/releases"

  # Off until the desktop app ships: every eligible recipient otherwise costs a
  # badge query and a broadcast per message, whether or not they run the app.
  def self.notifications_enabled?
    Rails.configuration.x.desktop_notifications_enabled
  end
end
