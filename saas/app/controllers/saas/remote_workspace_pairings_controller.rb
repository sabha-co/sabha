# frozen_string_literal: true

module Saas
  # An admin switching on Continue with sabha.co for a community in their
  # list: put the secret in the community's server environment, restart it,
  # then Verify. Adding a community can start this too.
  class RemoteWorkspacePairingsController < BaseController
    helper RemoteWorkspacesHelper

    # Each look-up and Verify fetches someone else's server
    rate_limit to: 10, within: 1.hour, only: :create, name: "pair", by: -> { current_global_identity.id }, with: :too_many_requests
    rate_limit to: 30, within: 1.hour, only: :update, name: "verify", by: -> { current_global_identity.id }, with: :too_many_requests

    before_action :set_pairing, only: %i[ show update ]

    # A new secret, shown on this one response and never again
    def create
      remote_workspace = current_global_identity.remote_workspace_memberships.find_by!(remote_workspace_id: params[:remote_workspace_id]).remote_workspace
      @pairing = current_global_identity.pair_remote_workspace!(remote_workspace)
      @show_secret = true
      render :show, status: :created
    rescue GlobalIdentity::RemoteWorkspaceClaimedError
      redirect_to settings_path, alert: "#{remote_workspace.address} already signs in with sabha.co another way."
    end

    def show
    end

    # Verify
    def update
      @pairing.verify!
      redirect_to settings_path, notice: "#{@pairing.remote_workspace.name} is connected to sabha.co"
    rescue RemoteWorkspacePairing::ProofMismatch
      redirect_to remote_workspace_pairing_path(@pairing),
        alert: "#{@pairing.remote_workspace.address} isn't running with this secret yet. Check SABHA_HUB_SECRET, restart it, then Verify again."
    rescue RemoteWorkspace::Probe::Error
      redirect_to remote_workspace_pairing_path(@pairing), alert: "We couldn't reach #{@pairing.remote_workspace.address}. Try again once it's back up."
    end

    private
      def set_pairing
        @pairing = current_global_identity.remote_workspace_pairings.find(params[:id])
        redirect_to settings_path, alert: "That request expired. Get a new secret from #{@pairing.remote_workspace.name}'s menu." if @pairing.expired?
      end

      def too_many_requests
        redirect_to settings_path, alert: "Too many attempts. Try again in an hour."
      end
  end
end
