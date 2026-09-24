# frozen_string_literal: true

module Saas
  class RemoteWorkspacesController < BaseController
    helper RemoteWorkspacesHelper

    # Each look-up fetches someone else's server, so keep people from using
    # sabha.co to hammer one. Opening the empty form fetches nothing. Each
    # limit is named so the two keep separate counts.
    rate_limit to: 30, within: 1.hour, only: :new, if: -> { params[:origin].present? }, name: "look-up",
      by: -> { current_global_identity.id }, with: :too_many_requests
    rate_limit to: 20, within: 1.hour, only: :create, name: "add", by: -> { current_global_identity.id }, with: :too_many_requests

    rescue_from RemoteWorkspace::Origin::Hub, with: :redirect_to_hub_workspace
    rescue_from RemoteWorkspace::Origin::Invalid, RemoteWorkspace::Probe::Error, GlobalIdentity::RemoteWorkspaceClaimedError,
      with: :render_lookup_failure

    # GET /remote_workspaces/new?origin=chat.acme.org
    # Shows the community's name and address to confirm before listing it,
    # or says it's already listed.
    def new
      @address = params[:origin].to_s
      @remote_workspace = RemoteWorkspace.preview(@address) if @address.present?
      @membership = current_global_identity.remote_workspace_membership_for(@remote_workspace) if @remote_workspace
    end

    # An admin can tick "I run this community" to get a secret for Continue
    # with sabha.co. It's shown on this one response and never again.
    def create
      remote_workspace = RemoteWorkspace.preview(params[:origin])
      return redirect_to_listed(remote_workspace) if listed_elsewhere?(remote_workspace)

      @pairing = current_global_identity.pair_remote_workspace!(remote_workspace) if params[:pair] == "1"
      current_global_identity.list_remote_workspace!(@pairing&.remote_workspace || remote_workspace, source: params[:source] == "prompt" ? :prompt : :added)

      if @pairing
        @show_secret = true
        render "saas/remote_workspace_pairings/show", status: :created
      else
        redirect_to settings_path, notice: "#{remote_workspace.name} is in your list"
      end
    rescue GlobalIdentity::RemoteWorkspaceLimitReachedError
      redirect_to settings_path, alert: "Your list is full. Remove a community to add another."
    end

    private
      def listed_elsewhere?(remote_workspace)
        membership = current_global_identity.remote_workspace_membership_for(remote_workspace)
        membership && membership.remote_workspace.origin != remote_workspace.origin
      end

      def redirect_to_listed(remote_workspace)
        listed = current_global_identity.remote_workspace_membership_for(remote_workspace).remote_workspace
        redirect_to settings_path, notice: "#{listed.name} is already in your list as #{listed.address}"
      end

      def redirect_to_hub_workspace(error)
        redirect_to error.workspace_id ? "/#{error.workspace_id}" : workspaces_path
      end

      def render_lookup_failure(error)
        @address = params[:origin].to_s
        @lookup_error = error
        render :new, status: :unprocessable_entity
      end

      def too_many_requests
        redirect_to settings_path, alert: "Too many look-ups. Try again in an hour."
      end
  end
end
