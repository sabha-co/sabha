# Centralized branding configuration for Campfire-CE
# All branding elements are configured through environment variables
# This allows anyone to run their own branded community without code changes
#
# Access via: Rails.configuration.x.branding.app_name
# Or shortcut: Branding.app_name

Rails.application.configure do
  # Initialize the branding namespace explicitly
  config.x.branding = ActiveSupport::OrderedOptions.new

  config.x.branding.app_name = ENV.fetch("APP_NAME", "Campfire Community Edition")
  config.x.branding.app_short_name = ENV.fetch("APP_SHORT_NAME") { config.x.branding.app_name }
  config.x.branding.support_email = ENV.fetch("SUPPORT_EMAIL", "support@example.com")
  config.x.branding.app_host = ENV.fetch("APP_HOST", "localhost")
  config.x.branding.app_description = ENV.fetch("APP_DESCRIPTION", "A community chat platform powered by Campfire-CE")

  # Mailer configuration
  config.x.branding.mailer_from_name = ENV.fetch("MAILER_FROM_NAME") { config.x.branding.app_name }
  config.x.branding.mailer_from_email = ENV.fetch("MAILER_FROM_EMAIL") { config.x.branding.support_email }

  # PWA theme colors
  config.x.branding.theme_color = ENV.fetch("THEME_COLOR", "#1d4ed8")
  config.x.branding.background_color = ENV.fetch("BACKGROUND_COLOR", "#ffffff")

  # Analytics (optional)
  config.x.branding.analytics_domain = ENV.fetch("ANALYTICS_DOMAIN", nil)

  # CSP frame ancestors
  default_ancestors = "https://#{config.x.branding.app_host}, https://*.#{config.x.branding.app_host}"
  config.x.branding.csp_frame_ancestors = ENV.fetch("CSP_FRAME_ANCESTORS", default_ancestors).split(",").map(&:strip)
end

# Convenience module for cleaner access throughout the app
# Usage: Branding.app_name instead of Rails.configuration.x.branding.app_name
module Branding
  class << self
    delegate :app_name, :app_short_name, :support_email, :app_host, :app_description,
             :mailer_from_name, :mailer_from_email, :theme_color, :background_color,
             :analytics_domain, :csp_frame_ancestors,
             to: :config

    def app_url
      protocol = Rails.env.production? ? "https" : "http"
      "#{protocol}://#{app_host}"
    end

    def mailer_from
      "#{mailer_from_name} <#{mailer_from_email}>"
    end

    private

    def config
      Rails.configuration.x.branding
    end
  end
end
