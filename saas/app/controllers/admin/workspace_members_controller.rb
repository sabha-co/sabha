# frozen_string_literal: true

module Admin
  class WorkspaceMembersController < BaseController
    before_action :set_workspace

    def index
      @query = params[:query]

      last_active_subquery = GlobalSession
        .select("global_identity_id, MAX(last_active_at) AS last_active_at")
        .group(:global_identity_id)

      scope = WorkspaceMembership
        .where(tenant: @workspace.external_id.to_s)
        .joins(:global_identity)
        .joins("LEFT JOIN (#{last_active_subquery.to_sql}) last_sessions ON last_sessions.global_identity_id = workspace_memberships.global_identity_id")
        .includes(:global_identity)
        .select("workspace_memberships.*, last_sessions.last_active_at AS last_active_at")

      if @query.present?
        scope = scope.where("global_identities.email_address ILIKE :q OR global_identities.name ILIKE :q", q: "%#{@query}%")
      end

      @memberships = scope.order("last_sessions.last_active_at DESC NULLS LAST")
    end

    private

      def set_workspace
        @workspace = Workspace.find(params[:workspace_id])
      end
  end
end
