# frozen_string_literal: true

module Saas
  class WorkspaceSettingsController < ApplicationController
    before_action :set_workspace
    before_action :ensure_administrator, only: [ :destroy ]

    def show
      @membership = Current.workspace_membership
      @is_last_admin = @workspace.last_administrator?(Current.user)
      @member_count = User.active.count
    end

    def destroy
      unless params[:confirmation] == @workspace.name
        redirect_to settings_path, alert: "Workspace name did not match."
        return
      end

      name = @workspace.name
      @workspace.destroy_with_database!
      redirect_to workspaces_url(script_name: ""), notice: "#{name} has been deleted"
    end

    private

      def set_workspace
        @workspace = Current.workspace
      end

      def ensure_administrator
        head :forbidden unless Current.user.administrator?
      end
  end
end
