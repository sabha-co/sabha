# frozen_string_literal: true

module Saas
  class BaseController < ActionController::Base
    # Base controller for SaaS routes that operate outside workspace context.
    #
    # Inherits directly from ActionController::Base to bypass the core
    # ApplicationController's Authentication concern which tries to access
    # tenanted Session models.
    #
    # Use this for:
    # - Landing page
    # - Login/signup (GlobalIdentity authentication)
    # - Workspace management
    # - Magic link verification

    protect_from_forgery with: :exception

    include Saas::Authentication
    include SetCurrentRequest

    # Include core helpers for consistent UI (icon_tag, translation_button, etc.)
    helper ApplicationHelper
    helper TranslationsHelper
    helper WorkspaceSelectorHelper
    helper TenantingHelper

    # Require GlobalIdentity authentication by default
    # Controllers can use `allow_unauthenticated_access` to skip
    require_authentication

    # Load workspaces for sidebar
    before_action :load_workspaces_for_sidebar

    layout "saas"

    private

      def load_workspaces_for_sidebar
        return unless signed_in?

        @workspaces = current_global_identity.active_workspaces_recent_first
      end
  end
end
