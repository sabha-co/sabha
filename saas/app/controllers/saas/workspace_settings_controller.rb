# frozen_string_literal: true

module Saas
  class WorkspaceSettingsController < ApplicationController
    before_action :set_workspace

    def show
      @membership = Current.workspace_membership
      @is_last_admin = @workspace.last_administrator?(Current.user)
      @member_count = User.member_count
    end

    private

      def set_workspace
        @workspace = Current.workspace
      end
  end
end
