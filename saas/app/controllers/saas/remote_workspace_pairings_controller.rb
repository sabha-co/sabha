# frozen_string_literal: true

module Saas
  # An admin pairing their community with sabha.co: paste its address, put the
  # secret in the community's settings, restart it, then Verify.
  class RemoteWorkspacePairingsController < BaseController
    helper RemoteWorkspacesHelper

    # Each look-up and Verify fetches someone else's server
    rate_limit to: 10, within: 1.hour, only: :create, by: -> { current_global_identity.id }, with: :too_many_requests
    rate_limit to: 30, within: 1.hour, only: :update, by: -> { current_global_identity.id }, with: :too_many_requests

    before_action :set_pairing, only: %i[ show update ]

    def new
      @address = params[:origin].to_s
    end

    # The secret is shown on this one response and never again
    def create
      @pairing = current_global_identity.pair_remote_workspace!(RemoteWorkspace.preview(params[:origin]))
      @show_secret = true
      render :show, status: :created
    rescue RemoteWorkspace::Origin::Invalid, RemoteWorkspace::Origin::Hub, RemoteWorkspace::Probe::Error,
        GlobalIdentity::RemoteWorkspaceClaimedError => error
      @address = params[:origin].to_s
      @lookup_error = error
      render :new, status: :unprocessable_entity
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
        redirect_to new_remote_workspace_pairing_path(origin: @pairing.remote_workspace.origin), alert: "That request expired. Start again for a new secret." if @pairing.expired?
      end

      def too_many_requests
        redirect_to settings_path, alert: "Too many attempts. Try again in an hour."
      end
  end
end
