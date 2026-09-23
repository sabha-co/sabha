# frozen_string_literal: true

module Saas
  class SingleSignOnsController < BaseController
    include SingleSignOnRequest

    allow_unauthenticated_access

    def show
      unless signed_in?
        return redirect_to new_session_path(return_to: request.fullpath), alert: "Please sign in to continue"
      end

      if @remote_workspace
        return render :consent unless current_global_identity.consented_to_remote_workspace?(@remote_workspace)

        current_global_identity.signed_in_to_remote_workspace!(@remote_workspace)
      end

      sso, sig = Sso::Payload.encode(sso_response_payload, @sso_client.secret)

      redirect_to return_sso_url(sso:, sig:), allow_other_host: true
    end

    private

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
