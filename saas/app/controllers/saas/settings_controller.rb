# frozen_string_literal: true

module Saas
  class SettingsController < BaseController
    # Global settings management (email + workspace list)
    #
    # This page is accessible via the gear icon in workspace selector.
    # It allows users to:
    # - Edit their email (triggers re-verification)
    # - View all workspaces they belong to with their role
    # - Navigate to workspace-specific settings (leave/delete)

    def show
      @global_identity = current_global_identity
      @workspace_memberships = current_global_identity.workspace_memberships_with_workspaces
      set_communities
      @workspace_access_denied = params[:denied] == "workspace"
    end

    def update
      @global_identity = current_global_identity

      if @global_identity.initiate_email_change!(settings_params[:email_address])
        redirect_to auth_code_path, notice: "Enter the verification code sent to #{@global_identity.unconfirmed_email}"
      else
        redirect_to settings_path, notice: "No changes made"
      end
    rescue ActiveRecord::RecordInvalid
      @workspace_memberships = current_global_identity.workspace_memberships_with_workspaces
      set_communities
      render :show, status: :unprocessable_entity
    end

    private

      def set_communities
        @remote_workspace_memberships = current_global_identity.remote_workspace_memberships.alphabetically
        @paired_remote_workspaces = current_global_identity.paired_remote_workspaces.pairing_active.order(:name)
        @remote_workspace_pairings = current_global_identity.remote_workspace_pairings.pending.includes(:remote_workspace).order(created_at: :desc)
      end

      def settings_params
        params.require(:global_identity).permit(:email_address)
      end
  end
end
