# frozen_string_literal: true

module Saas
  class RemoteWorkspaceListsController < BaseController
    # Forget every self-hosted community in the person's list. Their accounts
    # on those communities are untouched.
    def destroy
      current_global_identity.remote_workspace_memberships.destroy_all
      redirect_to settings_path, notice: "Your list of communities is cleared"
    end
  end
end
