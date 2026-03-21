# frozen_string_literal: true

module Admin
  class WorkspaceBackupsController < BaseController
    before_action :set_workspace

    def index
      @backups = @workspace.backups.order(created_at: :desc)
    end

    def create
      unless Workspace::Backup.r2_configured?
        return redirect_to admin_workspace_backups_path(@workspace), alert: "Backups are not configured. Set R2 credentials to enable."
      end

      Workspace::BackupJob.perform_later(@workspace)
      redirect_to admin_workspace_backups_path(@workspace), notice: "Backup queued for #{@workspace.name}."
    end

    private

      def set_workspace
        @workspace = Workspace.find(params[:workspace_id])
      end
  end
end
