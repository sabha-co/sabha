# frozen_string_literal: true

module Saas
  module Platform
    # Sabha Cloud pairing the droplets it provisions, so their owners can use
    # "Continue with sabha.co" from the first day. Only the platform's token
    # gets in; nobody signs in here.
    class RemoteWorkspacesController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :authenticate_platform

      rescue_from RemoteWorkspace::Origin::Invalid, RemoteWorkspace::Origin::Hub do |error|
        render json: { error: error.message }, status: :unprocessable_entity
      end

      def create
        remote_workspace = RemoteWorkspace.pair_sabha_cloud!(params.require(:origin), name: params.require(:name), owner_email: params[:owner_email])

        render json: { origin: remote_workspace.origin, secret: remote_workspace.secret, listed: remote_workspace.listed_by?(params[:owner_email]) },
          status: :created
      end

      # The droplet is gone. Its owner keeps the entry until they remove it.
      def destroy
        remote_workspace = RemoteWorkspace.find_by!(origin: RemoteWorkspace::Origin.normalize(params[:id]))
        remote_workspace.disconnect! if remote_workspace.pairing_active?

        head :no_content
      rescue ActiveRecord::RecordNotFound
        head :not_found
      end

      private
        def authenticate_platform
          authenticate_or_request_with_http_token do |token|
            expected = ENV["SABHA_PLATFORM_TOKEN"]
            expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
          end
        end
    end
  end
end
