# frozen_string_literal: true

module Saas
  class LandingController < BaseController
    # SaaS landing page - the root "/" in SaaS mode
    #
    # - Not signed in → renders marketing landing page
    # - Signed in with workspaces → redirect to most recent workspace
    # - Signed in without workspaces → redirect to create workspace
    # - The desktop app never sees it: sign-in or its workspace instead

    allow_unauthenticated_access

    layout "marketing"

    before_action :redirect_desktop_away_from_marketing

    def show
      redirect_to_workspace_or_create if signed_in?
    end
  end
end
