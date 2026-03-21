# frozen_string_literal: true

module Admin
  class WorkspaceMembersController < BaseController
    before_action :set_workspace

    def index
      @query = params[:query]
      @memberships = WorkspaceMembership.for_workspace(@workspace).search(@query).by_last_active
      @members_count = @memberships.size
    end

    private

      def set_workspace
        @workspace = Workspace.find(params[:workspace_id])
      end
  end
end
