# frozen_string_literal: true

module Saas
  class SingleSignOnsController < BaseController
    include ::DesktopHandoff

    allow_unauthenticated_access

    before_action :set_sso_request
    before_action :store_desktop_handoff_context, only: :show

    def show
      unless signed_in?
        return redirect_to new_session_path(return_to: request.fullpath), alert: "Please sign in to continue"
      end

      handoff = desktop_handoff_context
      clear_desktop_handoff_context
      if handoff.present?
        claim = Desktop::GlobalSessionClaim.issue!(
          global_identity: current_global_identity,
          nonce: handoff["nonce"],
          origin: handoff["origin"],
          return_path: handoff["return_path"]
        )
        return redirect_to_desktop_claim!(claim)
      end

      sso, sig = Sso::Payload.encode(sso_response_payload, @sso_client.secret)

      redirect_to return_sso_url(sso:, sig:), allow_other_host: true
    end

    private

      def set_sso_request
        @sso_client, @sso_request = Sso::ProviderClient.authenticate(params[:sso], params[:sig])
      rescue Sso::ProviderClient::NotConfigured
        head :service_unavailable
      rescue Sso::Payload::Error, Sso::ProviderClient::Error
        head :forbidden
      end

      def sso_response_payload
        {
          nonce: @sso_request["nonce"],
          external_id: "global_identity:#{current_global_identity.id}",
          email: current_global_identity.email_address,
          name: current_global_identity.name,
          require_activation: !current_global_identity.verified?
        }
      end

      def return_sso_url(sso:, sig:)
        uri = URI.parse(@sso_request["return_sso_url"])
        query = Rack::Utils.parse_query(uri.query).merge("sso" => sso, "sig" => sig)
        uri.query = Rack::Utils.build_query(query)
        uri.to_s
      end
  end
end
