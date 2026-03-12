# frozen_string_literal: true

module Admin
  class StatsController < BaseController
    def show
      @total_workspaces = Workspace.count
      @active_workspaces = Workspace.active.count
      @suspended_workspaces = Workspace.suspended.count
      @new_workspaces_last_30_days = Workspace.where(created_at: 30.days.ago..).count

      @total_identities = GlobalIdentity.count
      @verified_identities = GlobalIdentity.verified.count
      @new_identities_last_30_days = GlobalIdentity.where(created_at: 30.days.ago..).count

      @recent_workspaces = Workspace.order(created_at: :desc).limit(5).includes(:creator)
      @recent_signups = GlobalIdentity.order(created_at: :desc).limit(5)
    end
  end
end
