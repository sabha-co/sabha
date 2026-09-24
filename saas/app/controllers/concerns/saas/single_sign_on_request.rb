# frozen_string_literal: true

# A signed request from a workspace asking sabha.co who someone is. A paired
# workspace is found by the address it wants the answer sent to; everyone
# else is an env-configured client.
module Saas::SingleSignOnRequest
  extend ActiveSupport::Concern

  included do
    before_action :set_sso_request
  end

  private
    def set_sso_request
      @remote_workspace, @sso_request = RemoteWorkspace.authenticate_sign_in(params[:sso], params[:sig])
      @sso_client, @sso_request = @remote_workspace ? [ @remote_workspace, @sso_request ] : Sso::ProviderClient.authenticate(params[:sso], params[:sig])
    rescue RemoteWorkspace::DisconnectedError => error
      @remote_workspace = error.remote_workspace
      render "saas/single_sign_ons/disconnected", status: :forbidden
    rescue Sso::ProviderClient::NotConfigured
      head :service_unavailable
    rescue RemoteWorkspace::NotPairedError, Sso::Payload::Error, Sso::ProviderClient::Error
      head :forbidden
    end
end
