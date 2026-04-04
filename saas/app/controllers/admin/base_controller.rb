# frozen_string_literal: true

module Admin
  # Base controller for platform admin area (/admin).
  #
  # Operates entirely on the untenanted PostgreSQL database (GlobalIdentity,
  # Workspace, WorkspaceMembership). Does NOT access per-workspace SQLite
  # databases. To query tenanted data in the future, wrap calls in
  # ApplicationRecord.with_tenant(workspace.external_id.to_s).
  class BaseController < Saas::BaseController
    before_action :ensure_superadmin

    layout "admin"
    helper AdminHelper

    skip_before_action :load_workspaces_for_sidebar

    private

      def ensure_superadmin
        head :forbidden unless current_global_identity&.superadmin?
      end

      # Sorting support — subclasses define SORTABLE_COLUMNS and DEFAULT_SORT
      def sort_column
        col = params[:sort]
        self.class::SORTABLE_COLUMNS.include?(col) ? col : self.class::DEFAULT_SORT
      end

      def sort_direction
        params[:direction] == "asc" ? "asc" : "desc"
      end

      PER_PAGE = 25

      helper_method :sort_column, :sort_direction
  end
end
