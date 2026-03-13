# frozen_string_literal: true

module Saas
  class WorkspaceInvitesController < ApplicationController
    layout "saas"

    before_action :ensure_administrator

    def show
    end

    private

      def ensure_administrator
        redirect_to root_path unless Current.user.can_administer?
      end
  end
end
