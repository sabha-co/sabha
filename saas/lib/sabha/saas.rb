# frozen_string_literal: true

require_relative "saas/engine"

module Sabha
  module Saas
    # SaaS layer for Sabha multi-tenancy
    #
    # This module provides:
    # - GlobalIdentity authentication (cross-workspace)
    # - Workspace isolation via activerecord-tenanted
    # - Path-based workspace routing
    # - Workspace selector UI
  end
end
