# frozen_string_literal: true

module Saas
  class RemoteWorkspaceMembershipsController < BaseController
    before_action :set_membership

    # Hide or show an entry in the selector
    def update
      @membership.update!(hidden: params.expect(remote_workspace_membership: [ :hidden ])[:hidden])
      redirect_to settings_path
    end

    def destroy
      @membership.destroy!
      redirect_to settings_path, notice: "#{@membership.remote_workspace.name} was removed from your list"
    end

    private
      def set_membership
        @membership = current_global_identity.remote_workspace_memberships.find(params[:id])
      end
  end
end
