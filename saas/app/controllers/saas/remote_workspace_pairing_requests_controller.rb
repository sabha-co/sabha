# frozen_string_literal: true

module Saas
  # An admin switching on Continue with sabha.co for a workspace in their
  # list: put the secret in the workspace's server environment, restart it,
  # then Verify. Adding a workspace can start this too.
  class RemoteWorkspacePairingRequestsController < BaseController
    helper RemoteWorkspacesHelper

    # Each look-up and Verify fetches someone else's server
    rate_limit to: 10, within: 1.hour, only: :create, name: "pair", by: -> { current_global_identity.id }, with: :too_many_requests
    rate_limit to: 30, within: 1.hour, only: :update, name: "verify", by: -> { current_global_identity.id }, with: :too_many_requests

    before_action :set_pairing_request, only: %i[ show update ]

    # A new secret, shown on this one response and never again
    def create
      remote_workspace = current_global_identity.remote_workspace_memberships.find_by!(remote_workspace_id: params[:remote_workspace_id]).remote_workspace
      @pairing_request = current_global_identity.request_remote_workspace_pairing!(remote_workspace)
      @show_secret = true
      render :show, status: :created
    rescue GlobalIdentity::RemoteWorkspaceHasSsoClientError
      redirect_to settings_path, alert: "#{remote_workspace.address} already signs in with sabha.co another way."
    end

    def show
    end

    # Verify
    def update
      @pairing_request.verify!
      redirect_to settings_path, notice: "#{@pairing_request.remote_workspace.name} is connected to sabha.co"
    rescue RemoteWorkspacePairingRequest::ProofMismatchError
      redirect_to remote_workspace_pairing_request_path(@pairing_request),
        alert: "#{@pairing_request.remote_workspace.address} isn't using this secret yet. Check SABHA_HUB_SECRET and restart it."
    rescue RemoteWorkspace::Probe::Error
      redirect_to remote_workspace_pairing_request_path(@pairing_request), alert: "Couldn't reach #{@pairing_request.remote_workspace.address}."
    end

    private
      def set_pairing_request
        @pairing_request = current_global_identity.remote_workspace_pairing_requests.find(params[:id])
        redirect_to settings_path, alert: "That request expired. Get a new secret from #{@pairing_request.remote_workspace.name}'s menu." if @pairing_request.expired?
      end

      def too_many_requests
        redirect_to settings_path, alert: "Too many attempts. Try again in an hour."
      end
  end
end
