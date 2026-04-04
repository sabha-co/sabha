# frozen_string_literal: true

module Admin
  class WorkspaceMembersController < BaseController
    before_action :set_workspace

    def index
      @query = params[:query]
      @memberships = WorkspaceMembership.for_workspace(@workspace).search(@query).by_last_active
      @members_count = @memberships.size

      # Batch-load user roles from tenanted DB
      user_ids = @memberships.filter_map(&:user_id)
      @roles_by_user_id = if user_ids.any?
        begin
          ApplicationRecord.with_tenant(@workspace.external_id.to_s) do
            User.where(id: user_ids).map { |u| [ u.id, u.role ] }.to_h
          end
        rescue ActiveRecord::Tenanted::TenantDoesNotExistError
          {}
        end
      else
        {}
      end
    end

    private

      def set_workspace
        @workspace = Workspace.find(params[:workspace_id])
      end
  end
end
