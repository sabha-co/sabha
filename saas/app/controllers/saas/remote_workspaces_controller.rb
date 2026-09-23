# frozen_string_literal: true

module Saas
  class RemoteWorkspacesController < BaseController
    helper RemoteWorkspacesHelper

    # Each look-up fetches someone else's server, so keep people from using
    # sabha.co to hammer one.
    rate_limit to: 30, within: 1.hour, only: :new, by: -> { current_global_identity.id }, with: :too_many_requests
    rate_limit to: 20, within: 1.hour, only: :create, by: -> { current_global_identity.id }, with: :too_many_requests

    rescue_from RemoteWorkspace::Origin::Hub, with: :redirect_to_hub_workspace
    rescue_from RemoteWorkspace::Origin::Invalid, RemoteWorkspace::Probe::Error, with: :render_lookup_failure

    # GET /remote_workspaces/new?origin=chat.acme.org
    # Shows the community's name and address to confirm before listing it.
    def new
      @address = params[:origin].to_s
      @remote_workspace = RemoteWorkspace.preview(@address) if @address.present?
    end

    def create
      remote_workspace = RemoteWorkspace.preview(params[:origin])
      current_global_identity.list_remote_workspace!(remote_workspace, source: params[:source] == "prompt" ? :prompt : :added)

      redirect_to settings_path, notice: "#{remote_workspace.name} is in your list"
    rescue GlobalIdentity::RemoteWorkspaceLimitReachedError
      redirect_to settings_path, alert: "Your list is full. Remove a community to add another."
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
