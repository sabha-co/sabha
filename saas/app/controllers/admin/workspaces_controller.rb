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
        .joins("LEFT JOIN (#{last_active_sql}) ws_activity ON ws_activity.tenant = CAST(workspaces.external_id AS TEXT)")
        .joins("LEFT JOIN (#{members_count_sql}) ws_members ON ws_members.tenant = CAST(workspaces.external_id AS TEXT)")
        .select("workspaces.*, ws_activity.last_active_at AS last_active_at, COALESCE(ws_members.cnt, 0) AS members_count")
        .includes(:creator)
        .then { |scope| sort_column.in?(%w[db_size storage]) ? scope : scope.order(sort_sql) }

      # Ruby-sorted columns need all records loaded, sorted, then paginated manually
      if sort_column.in?(%w[db_size storage])
        all_workspaces = @workspaces.to_a

        case sort_column
        when "db_size"
          all_workspaces.sort_by! { |w| w.database_size || 0 }
        when "storage"
          all_workspaces.sort_by! { |w| w.activity_snapshot[:storage_bytes] || 0 }
        end
        all_workspaces.reverse! if sort_direction == "desc"

        @current_page = [ params[:page].to_i, 1 ].max
        @total_pages = (all_workspaces.size.to_f / PER_PAGE).ceil
        @workspaces = all_workspaces.slice((@current_page - 1) * PER_PAGE, PER_PAGE) || []
      else
        set_page_and_extract_portion_from @workspaces, per_page: PER_PAGE
        @workspaces = @page.records
      end

      # Preload activity snapshots for the current page only
      @activity_by_workspace_id = @workspaces.each_with_object({}) do |w, hash|
        hash[w.id] = w.activity_snapshot
      end
    end

    def show
      @workspace = Workspace.find(params[:id])
      @members_count = WorkspaceMembership.where(tenant: @workspace.external_id.to_s).count
      @backups_count = @workspace.backups.count
      @activity = @workspace.activity_snapshot
      @database_size = @workspace.database_size
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
        else                      "workspaces.created_at"
        end
        nulls = sort_direction == "desc" ? "NULLS LAST" : "NULLS FIRST"
        Arel.sql("#{col} #{sort_direction} #{nulls}")
      end
  end
end
