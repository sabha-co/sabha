# frozen_string_literal: true

module Saas
  module RemoteWorkspaces
    # An admin disconnecting their workspace from sabha.co. Members keep it in
    # their lists and sign in there the usual way.
    class ConnectionsController < BaseController
      def destroy
        remote_workspace = current_global_identity.paired_remote_workspaces.pairing_active.find(params[:remote_workspace_id])
        remote_workspace.disconnect!

        redirect_to settings_path, notice: "#{remote_workspace.name} is disconnected from sabha.co"
      end
    end
  end
end
