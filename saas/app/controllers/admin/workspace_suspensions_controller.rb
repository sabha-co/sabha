# frozen_string_literal: true

module Admin
  # TODO: Right now, suspend! just sets a timestamp. It's a flag — not
  # enforcement. The workspace database and all its data are still fully
  # accessible if you know the URL. Need a before_action in the tenanted
  # request path that checks workspace.active? and redirects to the
  # workspace selector, plus ActionCable disconnect for live connections.
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
