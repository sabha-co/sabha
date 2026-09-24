# frozen_string_literal: true

module Saas
  module RemoteWorkspaces
    # Whoever paired a workspace ending its pairing: Continue with sabha.co
    # turns off, and members keep it in their lists and sign in the usual way.
    class PairingsController < BaseController
      def destroy
        remote_workspace = current_global_identity.paired_remote_workspaces.pairing_active.find(params[:remote_workspace_id])
        remote_workspace.disconnect!

        redirect_to settings_path, notice: "#{remote_workspace.name} is disconnected from sabha.co"
      end
    end
  end
end
