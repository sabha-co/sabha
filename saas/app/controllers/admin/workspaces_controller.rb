# frozen_string_literal: true

module Admin
  class WorkspacesController < BaseController
    SORTABLE_COLUMNS = %w[name created_at last_active members_count db_size storage].freeze
    DEFAULT_SORT = "created_at"

    def index
      @query = params[:query]

      last_active_sql = GlobalSession
        .joins("INNER JOIN workspace_memberships ON workspace_memberships.global_identity_id = global_sessions.global_identity_id")
        .select("workspace_memberships.tenant, MAX(global_sessions.last_active_at) AS last_active_at")
        .group("workspace_memberships.tenant").to_sql

      members_count_sql = WorkspaceMembership
        .select("tenant, COUNT(*) AS cnt")
        .group(:tenant).to_sql

      @workspaces = workspace_scope
        .left_joins(:snapshot)
        .joins("LEFT JOIN (#{last_active_sql}) ws_activity ON ws_activity.tenant = CAST(workspaces.external_id AS TEXT)")
        .joins("LEFT JOIN (#{members_count_sql}) ws_members ON ws_members.tenant = CAST(workspaces.external_id AS TEXT)")
        .select("workspaces.*, ws_activity.last_active_at AS last_active_at, COALESCE(ws_members.cnt, 0) AS members_count,
                 workspace_snapshots.messages_24h, workspace_snapshots.messages_7d,
                 workspace_snapshots.active_users, workspace_snapshots.storage_bytes,
                 workspace_snapshots.database_size AS snapshot_database_size")
        .includes(:creator)
        .order(sort_sql)

      set_page_and_extract_portion_from @workspaces, per_page: PER_PAGE
      @workspaces = @page.records
    end

    def show
      @workspace = Workspace.includes(:snapshot).find(params[:id])
      @members_count = WorkspaceMembership.where(tenant: @workspace.external_id.to_s).count
      @backups_count = @workspace.backups.count
    end

    private

      def workspace_scope
        return Workspace.all if @query.blank?
        Workspace.where("name ILIKE ?", "%#{Workspace.sanitize_sql_like(@query)}%")
      end

      def sort_sql
        col = case sort_column
        when "name"          then "workspaces.name"
        when "last_active"   then "ws_activity.last_active_at"
        when "members_count" then "ws_members.cnt"
        when "db_size"       then "workspace_snapshots.database_size"
        when "storage"       then "workspace_snapshots.storage_bytes"
        else                      "workspaces.created_at"
        end
        nulls = sort_direction == "desc" ? "NULLS LAST" : "NULLS FIRST"
        Arel.sql("#{col} #{sort_direction} #{nulls}")
      end
  end
end
