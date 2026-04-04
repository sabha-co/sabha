# frozen_string_literal: true

module Admin
  class WorkspaceSnapshotsController < BaseController
    def create
      workspace = Workspace.find(params[:workspace_id])
      workspace.refresh_snapshot!
      redirect_to admin_workspace_path(workspace), notice: "Snapshot refreshed."
    rescue ActiveRecord::Tenanted::TenantDoesNotExistError, ActiveRecord::RecordNotFound
      redirect_to admin_workspace_path(params[:workspace_id]), alert: "Could not refresh — workspace database unavailable."
    end
  end
end
