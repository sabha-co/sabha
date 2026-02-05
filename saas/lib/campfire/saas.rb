# frozen_string_literal: true

require_relative "saas/engine"

module Campfire
  module Saas
    # SaaS layer for Campfire multi-tenancy
    #
    # This module provides:
    # - GlobalIdentity authentication (cross-workspace)
    # - Workspace isolation via activerecord-tenanted
    # - Path-based workspace routing
    # - Workspace selector UI
  end
end
