class API::Desktop::BaseController < ApplicationController
  skip_forgery_protection
  include DesktopClientDetection

  skip_before_action :require_workspace_membership, raise: false

  before_action :require_supported_protocol_major

  private
    def protocol_major
      request.headers["Sabha-Desktop-Protocol-Major"]&.to_i
    end

    def require_supported_protocol_major
      return if protocol_major == Desktop::ClientManifest::PROTOCOL_MAJOR

      render json: Desktop::ClientManifest.unsupported(protocol_major), status: :unsupported_media_type
    end

    def request_authentication
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def require_authentication
      restore_authentication || bot_authentication || request_authentication
      return if performed?

      deny_inactive_workspace_user if Current.user.present?
    end

    def signed_in_for_desktop_api?
      if Sabha.saas?
        Current.global_identity.present?
      else
        Current.user.present?
      end
    end
end
