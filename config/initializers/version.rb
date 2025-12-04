Rails.application.config.app_version = ENV.fetch("APP_VERSION") {
  # Get latest git tag, fallback to "dev" if none
  `git describe --tags --abbrev=0 2>/dev/null`.strip.sub(/^v/, "").presence || "dev"
}
Rails.application.config.git_revision = ENV["GIT_REVISION"]
