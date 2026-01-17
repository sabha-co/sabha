require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Allow disabling SSL via DISABLE_SSL environment variable for local testing
  config.assume_ssl = ENV["DISABLE_SSL"].blank?

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = ENV["DISABLE_SSL"].blank?

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Use Redis for the shared cache store to match the existing production setup.
  config.cache_store = :redis_cache_store

  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Configure Resend as the email delivery method for production.
  config.action_mailer.delivery_method = :resend
  config.action_mailer.resend_settings = {
    api_key: ENV["RESEND_API_KEY"]
  }
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "localhost"), protocol: "https" }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # WebSocket URL (used by action_cable_meta_tag)
  # Both AnyCable and ActionCable use the same /cable path on the main domain
  config.action_cable.url = ENV.fetch("ANYCABLE_WEBSOCKET_URL", "wss://#{ENV.fetch('APP_HOST', 'localhost')}/cable")

  # Skip host authorization for health checks and internal RPC endpoints.
  # Health checks use Docker container IDs as hostnames.
  # AnyCable RPC uses Docker network aliases (campfire-web).
  config.host_authorization = {
    exclude: ->(request) { request.path == "/up" || request.path.start_with?("/_anycable") }
  }
end
