class API::Desktop::BaseController < ApplicationController
  skip_forgery_protection
  skip_before_action :require_workspace_membership, raise: false

  before_action :require_supported_protocol_major

  private
    def require_supported_protocol_major
      protocol_major = request.headers["Sabha-Desktop-Protocol-Major"]&.to_i
      return if protocol_major == Desktop::PROTOCOL_MAJOR

      render json: {
        error: "unsupported_protocol_major",
        requested_major: protocol_major,
        supported_major: Desktop::PROTOCOL_MAJOR,
        upgrade_url: Desktop::UPGRADE_URL
      }, status: :unsupported_media_type
    end

    def request_authentication
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def require_authentication
      restore_authentication || request_authentication
      return if performed?

      deny_inactive_workspace_user if Current.user.present?
    end
end
