# frozen_string_literal: true

module Admin
  class WorkspaceSuspensionsController < BaseController
    before_action :set_workspace

    def create
      @workspace.suspend!
      redirect_to admin_workspace_path(@workspace), notice: "#{@workspace.name} has been suspended."
    end

    def destroy
      @workspace.unsuspend!
      redirect_to admin_workspace_path(@workspace), notice: "#{@workspace.name} has been unsuspended."
    end

    private

      def set_workspace
        @workspace = Workspace.find(params[:workspace_id])
      end
  end
end
