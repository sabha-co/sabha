# frozen_string_literal: true

module Admin
  class BaseController < Saas::BaseController
    before_action :ensure_superadmin

    layout "admin"

    skip_before_action :load_workspaces_for_sidebar

    private

      def ensure_superadmin
        if current_global_identity
          redirect_to saas_root_path, alert: "Not authorized." unless current_global_identity.superadmin?
        else
          head :forbidden
        end
      end
  end
end
