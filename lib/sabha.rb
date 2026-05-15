# frozen_string_literal: true

module Sabha
  SAAS_MARKER = File.expand_path("../tmp/saas.txt", __dir__)

  class << self
    # Detect if SaaS mode is enabled.
    #
    # SaaS mode enables multi-tenancy features:
    # - GlobalIdentity for cross-workspace authentication
    # - Workspace isolation via activerecord-tenanted gem
    # - Path-based workspace routing (/{workspace_id}/...)
    #
    # Enable via:
    #   SAAS=true (environment variable)
    #   bin/rails saas:enable (creates tmp/saas.txt marker file)
    #
    def saas?
      return @saas if defined?(@saas)
      @saas = (ENV["SAAS"] == "true" || File.exist?(SAAS_MARKER)) && ENV["SAAS"] != "false"
    end

    # Configure Bundler to use SaaS Gemfile before boot
    # Called from bin/rails before require "config/boot"
    def configure_bundle
      if saas? && !ENV["BUNDLE_GEMFILE"]
        ENV["BUNDLE_GEMFILE"] = File.expand_path("../Gemfile.saas", __dir__)
      end
    end

    def reset_saas_detection!
      remove_instance_variable(:@saas) if defined?(@saas)
    end

    # Is an outbound-mail provider wired up? Self-hosted admins shouldn't see
    # email-toggle UI (and we shouldn't try to send) until provider creds are
    # actually configured. SaaS always returns true — the platform operator
    # owns delivery centrally. Dev/test always return true so letter_opener
    # and :test delivery work without needing a real API key.
    #
    # Platform kill switch for notification mail only: setting
    # EMAIL_GLOBALLY_DISABLED=true short-circuits this predicate to false,
    # which suppresses missed-notification bundles and the weekly digest
    # across every tenant with one env-var flip + restart. Transactional
    # auth mail (OTP, password reset, email verification) is intentionally
    # NOT gated by this predicate and keeps sending — locking users out of
    # sign-in is never the intended kill-switch outcome.
    def email_configured?
      return false if email_globally_disabled?
      return true if saas?
      return true if Rails.env.development? || Rails.env.test?

      case (ENV["EMAIL_PROVIDER"].presence || "resend")
      when "resend"
        ENV["RESEND_API_KEY"].present?
      when "ses"
        # aws-sdk-sesv2 only ships in Gemfile.saas, so SES_AVAILABLE is false on
        # self-hosted. Treat the EMAIL_PROVIDER=ses branch as truly available
        # only when the gem loaded — anything else would boot to "configured"
        # but raise at first send.
        defined?(SES_AVAILABLE) && SES_AVAILABLE
      else false
      end
    end

    def email_globally_disabled?
      ENV["EMAIL_GLOBALLY_DISABLED"] == "true"
    end
  end
end
