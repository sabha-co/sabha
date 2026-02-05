# frozen_string_literal: true

module Campfire
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
  end
end
