# An explicitly set APP_VERSION wins (baked into release images at build time);
# otherwise fall back to the git tag in a source checkout, then to "dev". A blank
# APP_VERSION is treated as unset, so a missing value degrades to the fallback
# instead of rendering an empty version.
Rails.application.config.app_version =
  ENV["APP_VERSION"].presence || `git describe --tags --always 2>/dev/null`.strip.presence || "dev"
