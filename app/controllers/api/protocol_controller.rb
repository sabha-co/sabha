# Base for endpoints any Sabha client reads: the desktop and mobile apps, and
# sabha.co when it checks a community.
class API::ProtocolController < ApplicationController
  skip_forgery_protection
  skip_before_action :require_workspace_membership, raise: false

  before_action :require_supported_protocol_major

  private
    def require_supported_protocol_major
      protocol_major = request.headers["Sabha-Protocol-Major"]&.to_i
      return if protocol_major == Sabha::PROTOCOL_MAJOR

      render json: {
        error: "unsupported_protocol_major",
        requested_major: protocol_major,
        supported_major: Sabha::PROTOCOL_MAJOR
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
