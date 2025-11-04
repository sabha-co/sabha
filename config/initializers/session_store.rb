session_options = {
  key: "_campfire_session",
  # Persist session cookie as permament so re-opened browser windows maintain a CSRF token
  expire_after: 20.years
}

# Only set domain if COOKIE_DOMAIN is present (avoid nil which causes Rack errors)
session_options[:domain] = ENV["COOKIE_DOMAIN"] if ENV["COOKIE_DOMAIN"].present?

Rails.application.config.session_store :cookie_store, **session_options
