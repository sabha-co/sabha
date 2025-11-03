Rails.application.config.session_store :cookie_store,
  key: "_campfire_session",
  domain: ENV["COOKIE_DOMAIN"],
  # Persist session cookie as permament so re-opened browser windows maintain a CSRF token
  expire_after: 20.years
