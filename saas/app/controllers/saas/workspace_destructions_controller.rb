# frozen_string_literal: true

module Saas
  class WorkspaceDestructionsController < ApplicationController
    before_action :ensure_administrator

    def create
      unless params[:confirmation] == Current.workspace.name
        redirect_to settings_path, alert: "Workspace name did not match."
        return
      end

      name = Current.workspace.name
      Current.workspace.destroy_with_database!
      redirect_to workspaces_url(script_name: ""), notice: "#{name} has been deleted"
    end

    private

      def ensure_administrator
        head :forbidden unless Current.user.administrator?
      end
  end
end
