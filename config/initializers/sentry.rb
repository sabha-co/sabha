if Rails.env.production? && ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
    config.send_default_pii = false
    config.release = ENV["APP_VERSION"]
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0.1).to_f

    # Don't report exceptions caused by normal user actions (bad URLs, expired tokens, bots probing)
    config.excluded_exceptions += [
      "ActionController::InvalidAuthenticityToken",
      "ActionController::UnknownFormat",
      "ActionController::BadRequest",
      "ActionDispatch::Http::MimeNegotiation::InvalidType",
      "ActionDispatch::Http::Parameters::ParseError",
      "ActiveRecord::Tenanted::TenantDoesNotExistError"
    ]
  end
end
