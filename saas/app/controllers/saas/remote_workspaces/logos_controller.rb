# frozen_string_literal: true

module Saas
  module RemoteWorkspaces
    # Serves the copy of a community's logo that sabha.co keeps, so the
    # community never sees who has it in their list. The logo is public on the
    # community itself, so anyone signed in may see it, including on the
    # confirm screen before they add it.
    class LogosController < BaseController
      def show
        remote_workspace = RemoteWorkspace.find(params[:remote_workspace_id])

        if !remote_workspace.logo?
          head :not_found
        elsif stale?(remote_workspace)
          expires_in 1.day
          send_data remote_workspace.logo_data, type: remote_workspace.logo_content_type, disposition: :inline
        end
      end
    end
  end
end
