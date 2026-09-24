# frozen_string_literal: true

module Saas
  class WorkspaceMembershipOrdersController < BaseController
    # PATCH /workspace_membership_order
    # Persists the user's drag-to-reorder of the selector, workspaces and
    # self-hosted workspaces in one sequence.
    def update
      if current_global_identity.reorder_switcher(params[:workspace_ids])
        head :ok
      else
        head :unprocessable_entity
      end
    end
  end
end
