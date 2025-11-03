require "active_support/core_ext/integer/time"
require "active_support/core_ext/numeric/bytes"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in either ENV["RAILS_MASTER_KEY"]
  # or in config/master.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Log to a file in storage
  config.logger = ActiveSupport::Logger.new("#{Rails.root}/storage/logs/production.log", 10, 100.megabytes)

  config.logger.formatter = proc do |severity, datetime, progname, msg|
    formatted_time = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%3N")
    "#{formatted_time} #{severity}: #{msg}\n"
  end
  config.logger = ActiveSupport::TaggedLogging.new(config.logger)

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # Info include generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). Use "debug"
  # for everything.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Cache in memory for now
  config.cache_store = :redis_cache_store

  # Assets are cacheable
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{30.days.to_i}"
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Always be SSL'ing (unless told not to)
  config.assume_ssl = ENV["DISABLE_SSL"].blank?
  config.force_ssl  = ENV["DISABLE_SSL"].blank?

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # SQLite is good, actually
  config.active_record.sqlite3_production_warning = false

  config.active_job.queue_adapter = :resque

  config.action_mailer.delivery_method = :resend
  config.action_mailer.resend_settings = {
    api_key: ENV['RESEND_API_KEY']
  }
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "localhost"), protocol: "https" }
end
