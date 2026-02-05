# frozen_string_literal: true

module Saas
  class LandingController < BaseController
    # SaaS landing page - the root "/" in SaaS mode
    #
    # Redirects based on authentication state:
    # - Not signed in → redirect to sign in
    # - Signed in with workspaces → redirect to most recent workspace
    # - Signed in without workspaces → redirect to create workspace

    allow_unauthenticated_access

    def show
      if signed_in?
        redirect_to_workspace_or_create
      else
        redirect_to new_session_path
      end
    end

    private

      def redirect_to_workspace_or_create
        workspaces = current_global_identity.active_workspaces_recent_first

        if workspaces.any?
          redirect_to "/#{workspaces.first.external_id}"
        else
          redirect_to new_workspace_path
        end
      end
  end
end
