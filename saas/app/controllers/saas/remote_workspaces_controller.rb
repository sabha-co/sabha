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
    rescue_from RemoteWorkspace::Origin::Invalid, RemoteWorkspace::Probe::Error, GlobalIdentity::RemoteWorkspaceHasSsoClientError,
      with: :render_lookup_failure

    # GET /remote_workspaces/new?origin=chat.acme.org
    # Shows the workspace's name and address to confirm before listing it,
    # or says it's already listed.
    def new
      @address = params[:origin].to_s
      @remote_workspace = RemoteWorkspace.preview(@address) if @address.present?
      @membership = current_global_identity.remote_workspace_membership_for(@remote_workspace) if @remote_workspace
    end

    # An admin can tick "I run this workspace" to get a secret for Continue
    # with sabha.co. It's shown on this one response and never again.
    def create
      remote_workspace = RemoteWorkspace.preview(params[:origin])
      @pairing_request = current_global_identity.request_remote_workspace_pairing!(remote_workspace) if params[:pair] == "1"
      current_global_identity.list_remote_workspace!(@pairing_request&.remote_workspace || remote_workspace, source: params[:source] == "prompt" ? :prompt : :added)

      if @pairing_request
        @show_secret = true
        render "saas/remote_workspace_pairing_requests/show", status: :created
      else
        redirect_to settings_path, notice: "#{remote_workspace.name} is in your list"
      end
    rescue GlobalIdentity::RemoteWorkspaceLimitReachedError
      redirect_to settings_path, alert: "Your list is full. Remove a workspace to add another."
    end

    private
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
