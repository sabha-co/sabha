# frozen_string_literal: true

module Saas
  class WorkspaceMembershipsController < BaseController
    # PATCH /workspace_memberships/reorder (untenanted)
    # Reorders workspace memberships for the current user based on drag-to-reorder
    def reorder
      if WorkspaceMembership.reorder_for_identity(current_global_identity, params[:workspace_ids])
        head :ok
      else
        head :unprocessable_entity
      end
    end

    # DELETE /membership (tenanted - leave current workspace)
    # Must be called within workspace context
    def destroy
      return head :not_found unless Current.workspace_membership

      workspace_name = Current.workspace.name
      Current.workspace_membership.leave!
      redirect_to workspaces_url(script_name: ""), notice: "You have left #{workspace_name}"
    rescue WorkspaceMembership::LastAdministratorError
      redirect_to settings_path, alert: "You cannot leave as the last administrator."
    end
  end
end
