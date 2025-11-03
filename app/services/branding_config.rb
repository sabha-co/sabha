# Centralized branding configuration for Smallbets Community Edition
# All branding elements should be configured through environment variables
# This allows anyone to run their own branded community without code changes
class BrandingConfig
  class << self
    # Application name used throughout the app
    def app_name
      ENV.fetch("APP_NAME", "Smallbets Community Edition")
    end

    # Short name for mobile/PWA
    def app_short_name
      ENV.fetch("APP_SHORT_NAME", app_name)
    end

    # Support email address for error messages and help
    def support_email
      ENV.fetch("SUPPORT_EMAIL", "support@example.com")
    end

    # Primary domain for the application
    def app_host
      ENV.fetch("APP_HOST", "localhost")
    end

    # Full URL with protocol
    def app_url
      protocol = Rails.env.production? ? "https" : "http"
      "#{protocol}://#{app_host}"
    end

    # Mailer "from" configuration
    def mailer_from_name
      ENV.fetch("MAILER_FROM_NAME", app_name)
    end

    def mailer_from_email
      ENV.fetch("MAILER_FROM_EMAIL", support_email)
    end

    def mailer_from
      "#{mailer_from_name} <#{mailer_from_email}>"
    end

    # Analytics domain (optional)
    def analytics_domain
      ENV.fetch("ANALYTICS_DOMAIN", nil)
    end

    # CSP frame ancestors (comma-separated list)
    def csp_frame_ancestors
      default = "https://#{app_host}, https://*.#{app_host}"
      ENV.fetch("CSP_FRAME_ANCESTORS", default).split(",").map(&:strip)
    end

    # PWA theme colors
    def theme_color
      ENV.fetch("THEME_COLOR", "#1d4ed8")
    end

    def background_color
      ENV.fetch("BACKGROUND_COLOR", "#ffffff")
    end

    # Default app description
    def app_description
      ENV.fetch("APP_DESCRIPTION", "A community chat platform powered by Smallbets Community Edition")
    end
  end
end
