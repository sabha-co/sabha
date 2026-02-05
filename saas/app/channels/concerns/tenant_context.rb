# frozen_string_literal: true

# Provides tenant context for ActionCable channels in SaaS mode
#
# Note: The activerecord-tenanted gem provides automatic tenant context via
# `around_command :with_tenant` in CableConnection::Base. This means all
# channel commands (subscribed, actions, etc.) are automatically wrapped
# in tenant context.
#
# This concern provides:
# - `with_tenant_context` - explicit helper for wrapping DB operations
#
module TenantContext
  extend ActiveSupport::Concern

  private

    def with_tenant_context(&block)
      tenant = respond_to?(:current_tenant) ? current_tenant : nil
      if Campfire.saas? && tenant.present?
        ApplicationRecord.with_tenant(tenant, &block)
      else
        yield
      end
    end
end
