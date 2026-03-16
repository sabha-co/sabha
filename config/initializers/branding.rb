# Centralized branding configuration for Sabha
#
# SaaS mode: values are hardcoded — Sabha is the product
# Self-hosted mode: values come from environment variables
#
# Access via: Branding.app_name, Branding.support_email, etc.

module Branding
  SAAS = {
    app_name: "Sabha",
    app_short_name: "Sabha",
    support_email: "ashwin@sabha.co",
    app_host: "sabha.co",
    app_description: "Community chat powered by Sabha",
    mailer_from_name: "Sabha",
    mailer_from_email: "ashwin@sabha.co",
    theme_color: "#1d4ed8",
    background_color: "#ffffff"
  }.freeze

  class << self
    def app_name
      saas? ? SAAS[:app_name] : config.app_name
    end

    def app_short_name
      saas? ? SAAS[:app_short_name] : config.app_short_name
    end

    def support_email
      saas? ? ENV.fetch("SUPPORT_EMAIL", SAAS[:support_email]) : config.support_email
    end

    def app_host
      saas? ? ENV.fetch("APP_HOST", SAAS[:app_host]) : config.app_host
    end

    def app_description
      saas? ? SAAS[:app_description] : config.app_description
    end

    def theme_color
      saas? ? SAAS[:theme_color] : config.theme_color
    end

    def background_color
      saas? ? SAAS[:background_color] : config.background_color
    end

    def app_url
      protocol = Rails.env.production? ? "https" : "http"
      "#{protocol}://#{app_host}"
    end

    # Inside a workspace: returns workspace name
    # Outside a workspace (or self-hosted): returns app_name
    def contextual_app_name
      if saas?
        Current.workspace&.name || app_name
      else
        app_name
      end
    end

    def mailer_from
      if saas?
        name = ENV.fetch("MAILER_FROM_NAME", SAAS[:mailer_from_name])
        email = ENV.fetch("MAILER_FROM_EMAIL", SAAS[:mailer_from_email])
        "#{name} <#{email}>"
      else
        "#{config.mailer_from_name} <#{config.mailer_from_email}>"
      end
    end

    # Analytics (optional, self-hosted only)
    delegate :umami_website_id, :umami_host, :csp_frame_ancestors, to: :config

    private

    def saas?
      Sabha.saas?
    end

    def config
      Rails.configuration.x.branding
    end
  end
end

# Self-hosted configuration from environment variables
Rails.application.configure do
  config.x.branding = ActiveSupport::OrderedOptions.new

  config.x.branding.app_name = ENV.fetch("APP_NAME", "Sabha")
  config.x.branding.app_short_name = ENV.fetch("APP_SHORT_NAME") { config.x.branding.app_name }
  config.x.branding.support_email = ENV.fetch("SUPPORT_EMAIL", "support@example.com")
  config.x.branding.app_host = ENV.fetch("APP_HOST", "localhost").presence || "localhost"
  config.x.branding.app_description = ENV.fetch("APP_DESCRIPTION", "A community chat platform powered by Sabha")

  config.x.branding.mailer_from_name = ENV.fetch("MAILER_FROM_NAME") { config.x.branding.app_name }
  config.x.branding.mailer_from_email = ENV.fetch("MAILER_FROM_EMAIL") { config.x.branding.support_email }

  config.x.branding.theme_color = ENV.fetch("THEME_COLOR", "#1d4ed8")
  config.x.branding.background_color = ENV.fetch("BACKGROUND_COLOR", "#ffffff")

  config.x.branding.umami_website_id = ENV.fetch("UMAMI_WEBSITE_ID", nil)
  config.x.branding.umami_host = ENV.fetch("UMAMI_HOST", "cloud.umami.is")

  default_ancestors = "https://#{config.x.branding.app_host}, https://*.#{config.x.branding.app_host}"
  config.x.branding.csp_frame_ancestors = ENV.fetch("CSP_FRAME_ANCESTORS", default_ancestors).split(",").map(&:strip)
end
