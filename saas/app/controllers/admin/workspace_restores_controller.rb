# frozen_string_literal: true

module Admin
  class WorkspaceRestoresController < BaseController
    before_action :set_backup

    def create
      Workspace::RestoreJob.perform_later(@backup.workspace, @backup)
      redirect_to admin_workspace_backups_path(@backup.workspace), notice: "Restore queued from #{@backup.created_at.to_fs(:short)}."
    end

    private

      def set_backup
        workspace = Workspace.find(params[:workspace_id])
        @backup = workspace.backups.find(params[:backup_id])
      end
  end
end
