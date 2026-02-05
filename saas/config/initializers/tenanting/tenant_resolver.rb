# frozen_string_literal: true

# Path-based workspace routing for SaaS mode
#
# Two pieces work together:
# 1. PathRewriter middleware: extracts workspace ID from path, rewrites PATH_INFO
# 2. Tenant resolver: returns the stashed workspace ID for TenantSelector

return unless defined?(ActiveRecord::Tenanted) && Campfire.saas?
return if @_campfire_saas_tenant_resolver_loaded
@_campfire_saas_tenant_resolver_loaded = true

require_relative "../../../lib/campfire/saas/path_rewriter"

# Insert PathRewriter BEFORE TenantSelector (which is at the end of the stack)
Rails.application.config.middleware.insert_before(
  ActiveRecord::Tenanted::TenantSelector,
  Campfire::Saas::PathRewriter
)

# Tenant resolver reads the workspace ID stashed by PathRewriter
Rails.application.config.active_record_tenanted.tenant_resolver = ->(request) do
  request.env["campfire.workspace_id"]
end
