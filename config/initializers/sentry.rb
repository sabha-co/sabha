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

# Rails extracted WebSocket handling into ActionCable::Server::Socket, which calls
# connection.handle_open / handle_close *publicly* — and AnyCable's "next" connection
# driver (selected once ActionCable::Server::Socket exists) does the same, calling
# conn.handle_open with an explicit receiver. sentry-rails (through 7.0.0) still prepends
# these onto the connection as *private*, so the external call raises NoMethodError and
# every WebSocket connection dies. Restore public visibility on Sentry's module until
# sentry-ruby adapts. This runs in every environment because the prepend is registered by
# sentry-rails' railtie, not by Sentry.init. Registered from after_initialize so our
# on_load hook queues after sentry-rails' own (on_load callbacks fire in registration order).
#
# Still unfixed as of sentry-rails 7.0.0 — tracked at
# https://github.com/getsentry/sentry-ruby/issues/2975. The guard below makes this a no-op
# once the methods ship public, so it's safe to leave until then.
Rails.application.config.after_initialize do
  ActiveSupport.on_load(:action_cable_connection) do
    if defined?(Sentry::Rails::ActionCableExtensions::Connection)
      Sentry::Rails::ActionCableExtensions::Connection.class_eval do
        # Guard per method: a future sentry-rails rename would make `public` on a missing
        # method raise NameError at boot. Only flip methods that actually exist.
        %i[ handle_open handle_close ].each do |method|
          public method if method_defined?(method) || private_method_defined?(method)
        end
      end
    end
  end
end
