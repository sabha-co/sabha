if Rails.env.production? && ENV["SKIP_TELEMETRY"].blank?
  Sentry.init do |config|
    config.dsn = "https://975a8bf631edee43b6a8cf4823998d92@o33603.ingest.sentry.io/4506587182530560"
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
    config.send_default_pii = false
    config.release = ENV["GIT_REVISION"]
  end
end
