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

      @workspace_growth = daily_counts_for(Workspace)
      @identity_growth = daily_counts_for(GlobalIdentity)

      @recent_workspaces = Workspace.order(created_at: :desc).limit(5).includes(:creator)
      @recent_signups = GlobalIdentity.order(created_at: :desc).limit(5)
    end

    private

      def daily_counts_for(model)
        raw = model.where(created_at: 30.days.ago.beginning_of_day..)
          .group("DATE(created_at)").count

        (0..29).map do |days_ago|
          date = days_ago.days.ago.to_date
          [ date, raw[date] || raw[date.to_s] || 0 ]
        end.reverse
      end
  end
end
