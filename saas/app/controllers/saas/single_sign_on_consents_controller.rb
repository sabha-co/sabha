# frozen_string_literal: true

module Saas
  # "Allow Acme to see your name and email?" The first time someone signs in
  # to a paired workspace with sabha.co, they approve it once.
  class SingleSignOnConsentsController < BaseController
    include SingleSignOnRequest

    def create
      return head :forbidden unless @remote_workspace

      current_global_identity.consent_to_remote_workspace!(@remote_workspace)
      redirect_to "/session/sso?#{{ sso: params[:sso], sig: params[:sig] }.to_query}"
    rescue GlobalIdentity::RemoteWorkspaceLimitReachedError
      redirect_to settings_path, alert: "Your list is full. Remove a workspace, then sign in to #{@remote_workspace.name} again."
    end
  end
end
