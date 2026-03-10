# frozen_string_literal: true

module Saas
  class LandingController < BaseController
    # SaaS landing page - the root "/" in SaaS mode
    #
    # - Not signed in → renders marketing landing page
    # - Signed in with workspaces → redirect to most recent workspace
    # - Signed in without workspaces → redirect to create workspace

    allow_unauthenticated_access

    layout "marketing"

    def show
      if signed_in?
        redirect_to_workspace_or_create
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
