# frozen_string_literal: true

module Saas
  class WorkspacesController < BaseController
    # Workspace management (outside workspace context)

    def index
      # Always redirect - workspace selection happens via sidebar, not this page
      workspaces = current_global_identity.active_workspaces_recent_first

      if workspaces.any?
        redirect_to "/#{workspaces.first.external_id}"
      else
        redirect_to new_workspace_path
      end
    end

    def new
    end

    def show
      @workspace = Workspace.find(params[:id])
      unless current_global_identity.workspace_memberships.exists?(tenant: @workspace.external_id.to_s)
        raise ActiveRecord::RecordNotFound
      end
      @invite_url = "/#{@workspace.external_id}/invite"
    end

    def create
      workspace = Workspace.create_with_database!(
        name: params[:name],
        creator: current_global_identity
      )

      redirect_to workspace_path(workspace)
    rescue GlobalIdentity::WorkspaceLimitReachedError
      flash.now[:alert] = "You've reached the maximum of #{GlobalIdentity::MAX_WORKSPACES} workspaces."
      render :new, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      # Extract error message safely - e.record may be from a tenanted model
      # that we can't access outside tenant context
      error_message = begin
        e.record.errors.full_messages.to_sentence
      rescue ActiveRecord::Tenanted::NoTenantError
        e.message.sub(/^Validation failed: /, "")
      end
      flash.now[:alert] = error_message
      render :new, status: :unprocessable_entity
    end
  end
end
