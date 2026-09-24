# frozen_string_literal: true

module Saas
  module RemoteWorkspaceMemberships
    # A member taking back their approval: sabha.co stops vouching for them to
    # the workspace until they approve it again.
    class ConsentsController < BaseController
      def destroy
        membership = current_global_identity.remote_workspace_memberships.find(params[:remote_workspace_membership_id])
        membership.revoke_consent!

        redirect_to settings_path, notice: "sabha.co won't sign you in to #{membership.remote_workspace.name} until you allow it again"
      end
    end
  end
end
