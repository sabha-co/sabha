# frozen_string_literal: true

module Admin
  class IdentitiesController < BaseController
    SORTABLE_COLUMNS = %w[email_address name workspaces_count created_at last_active].freeze
    DEFAULT_SORT = "created_at"

    def index
      @query = params[:query]

      last_active_sql = GlobalSession
        .select("global_identity_id, MAX(last_active_at) AS last_active_at")
        .group(:global_identity_id).to_sql

      workspace_counts_sql = WorkspaceMembership
        .select("global_identity_id, COUNT(*) AS cnt")
        .group(:global_identity_id).to_sql

      @identities = identity_scope
        .joins("LEFT JOIN (#{last_active_sql}) last_sessions ON last_sessions.global_identity_id = global_identities.id")
        .joins("LEFT JOIN (#{workspace_counts_sql}) ws_counts ON ws_counts.global_identity_id = global_identities.id")
        .select("global_identities.*, COALESCE(ws_counts.cnt, 0) AS workspaces_count, last_sessions.last_active_at AS last_active_at")
        .order(sort_sql)

      set_page_and_extract_portion_from @identities, per_page: PER_PAGE
      @identities = @page.records
    end

    def show
      @identity = GlobalIdentity.find(params[:id])
      @memberships = @identity.workspace_memberships.includes(:workspace)
    end

    private

      def identity_scope
        return GlobalIdentity.all if @query.blank?
        GlobalIdentity.where(
          "email_address ILIKE :q OR name ILIKE :q",
          q: "%#{GlobalIdentity.sanitize_sql_like(@query)}%"
        )
      end

      def sort_sql
        col = case sort_column
        when "email_address"    then "global_identities.email_address"
        when "name"             then "global_identities.name"
        when "workspaces_count" then "ws_counts.cnt"
        when "last_active"      then "last_sessions.last_active_at"
        else                         "global_identities.created_at"
        end
        nulls = sort_direction == "desc" ? "NULLS LAST" : "NULLS FIRST"
        Arel.sql("#{col} #{sort_direction} #{nulls}")
      end
  end
end
