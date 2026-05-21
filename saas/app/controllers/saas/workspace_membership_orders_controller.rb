# frozen_string_literal: true

module Saas
  class WorkspaceMembershipOrdersController < BaseController
    # PATCH /workspace_membership_order
    # Persists the user's drag-to-reorder of workspace icons in the sidebar.
    def update
      if WorkspaceMembership.reorder_for_identity(current_global_identity, params[:workspace_ids])
        head :ok
      else
        head :unprocessable_entity
      end
    end
  end
end
