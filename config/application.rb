require_relative "boot"
require_relative "../lib/sabha"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Sabha
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks rails_ext])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Fallback to English if translation key is missing
    config.i18n.fallbacks = true

    # Sabha always runs behind a reverse proxy (Kamal proxy or Caddy, sometimes
    # fronted by Cloudflare), so the real client IP comes from X-Forwarded-For.
    # The legacy Client-IP header is attacker-supplied — bots probing for exploits
    # inject a bogus one (e.g. 127.0.0.1) to trip Rails' spoofing check, turning
    # every probe into a noisy IpSpoofAttackError. X-Forwarded-For takes
    # precedence over Client-IP, so remote_ip is unchanged for real requests.
    config.action_dispatch.ip_spoofing_check = false

    # Encrypts the few secrets kept in the database, such as the secret sabha.co
    # shares with each workspace paired to it. Development and test set fixed
    # keys in their environment files.
    config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence

    console do
      if Sabha.saas?
        require_relative "../lib/console/tenant_helpers"
        TOPLEVEL_BINDING.eval("self").extend(Console::TenantHelpers)
        puts "  Tenant helpers: tenants, tenant(<id>), current_tenant, tenant_reset"
        puts ""
      end
    end
  end
end
