# frozen_string_literal: true

# Default Tenant for Development
#
# Sets a default tenant for console sessions and other contexts
# where no tenant is explicitly set.
#
# Can be overridden with ARTENANT environment variable:
#   ARTENANT=1000002 bin/rails console

return unless defined?(ActiveRecord::Tenanted) && Sabha.saas?

# Only set default tenant in development/test
if Rails.env.development? || Rails.env.test?
  Rails.application.config.active_record_tenanted.default_tenant = ENV.fetch("ARTENANT", "1000001")
end
