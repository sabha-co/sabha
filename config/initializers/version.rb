Rails.application.config.app_version = ENV.fetch("APP_VERSION") {
  `git describe --tags --always 2>/dev/null`.strip.presence || "dev"
}
