# frozen_string_literal: true

module Admin
  class WorkspaceSnapshotsController < BaseController
    def create
      workspace = Workspace.find(params[:workspace_id])
      Workspace::SnapshotJob.perform_later(workspace)
      redirect_to admin_workspace_path(workspace), notice: "Snapshot refresh queued."
    end
  end
end
