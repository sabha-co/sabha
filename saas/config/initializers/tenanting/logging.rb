# frozen_string_literal: true

# Tenant Logging
#
# Adds tenant identifier to logs for debugging and auditing:
# 1. Rails tagged logging - prefixes log lines with tenant=XXXXX
# 2. SQL query logs - includes tenant in query comments (requires query_log_tags_enabled)

return unless Sabha.saas?

# Add :tenant to SQL query log tags (if not already present)
# This shows the tenant in SQL log comments when query_log_tags_enabled = true
# Example: /*tenant:1000001*/ SELECT * FROM users
#
# Note: The gem may already add :tenant automatically, so we check first
Rails.application.config.active_record.query_log_tags ||= []
unless Rails.application.config.active_record.query_log_tags.include?(:tenant)
  Rails.application.config.active_record.query_log_tags << :tenant
end

# NOTE: This `to_prepare` block triggers a one-time premature-load-hook warning
# at boot in Rails 8.2+ (autoloading ApplicationController here cascades load
# hooks for :action_controller_base, :action_controller, :active_record, etc.).
# An `ActiveSupport.on_load(:action_controller_base)` rewrite WOULD silence the
# warning here — around_action attaches to the class's filter chain, which is
# inherited, so there is no MRO collision risk. Kept aligned with turbo.rb's
# class_eval pattern, which cannot be converted to on_load (see turbo.rb).
Rails.application.config.to_prepare do
  ApplicationController.class_eval do
    around_action :tag_logs_with_tenant, if: -> { Sabha.saas? }

    private

    def tag_logs_with_tenant
      tenant = ApplicationRecord.current_tenant

      if tenant.present? && Rails.logger.respond_to?(:tagged)
        Rails.logger.tagged("tenant=#{tenant}") { yield }
      else
        yield
      end
    end
  end
end
