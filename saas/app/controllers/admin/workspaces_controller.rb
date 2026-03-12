# frozen_string_literal: true

module Admin
  class WorkspacesController < BaseController
    def index
      @query = params[:query]
      @workspaces = workspace_scope.order(created_at: :desc).includes(:creator, :workspace_memberships)
    end

    def show
      @workspace = Workspace.find(params[:id])
      @memberships = WorkspaceMembership
        .where(tenant: @workspace.external_id.to_s)
        .includes(:global_identity)
        .order(created_at: :asc)
    end

    private

      def workspace_scope
        return Workspace.all if @query.blank?
        Workspace.where("name ILIKE ?", "%#{@query}%")
      end
  end
end
