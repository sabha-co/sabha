# DiceBear avatar configuration
# Provides generated avatars for users without uploaded photos
#
# Access via: Rails.configuration.x.dicebear.enabled
# Or shortcut: Dicebear.enabled?

Rails.application.configure do
  config.x.dicebear = ActiveSupport::OrderedOptions.new

  config.x.dicebear.enabled = ENV.fetch("DICEBEAR_ENABLED", "true") == "true"
  config.x.dicebear.style = ENV.fetch("DICEBEAR_STYLE", "bottts-neutral")

  # Validate DICEBEAR_HOST to prevent SSRF attacks
  default_host = "https://api.dicebear.com"
  custom_host = ENV.fetch("DICEBEAR_HOST", default_host).presence

  config.x.dicebear.host = if custom_host.nil?
    default_host
  elsif URI.parse(custom_host).scheme == "https" || Rails.env.local?
    custom_host
  else
    Rails.logger.warn("DICEBEAR_HOST must use HTTPS in production, using default")
    default_host
  end
end

module Dicebear
  class << self
    delegate :enabled, :host, :style, to: :config

    def enabled?
      enabled
    end

    private

    def config
      Rails.configuration.x.dicebear
    end
  end
end
