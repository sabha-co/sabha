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
