# frozen_string_literal: true

module Saas
  class WorkspacesController < BaseController
    # Workspace management (outside workspace context)

    # Allow unauthenticated access to join page - users can sign up from there
    allow_unauthenticated_access only: :join

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

    def create
      workspace = Workspace.create_with_database!(
        name: params[:name],
        creator: current_global_identity
      )

      redirect_to "/#{workspace.external_id}", notice: "Workspace created!"
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
    rescue StandardError => e
      flash.now[:alert] = "Failed to create workspace. Please try again."
      Rails.logger.error("Workspace creation failed: #{e.class} - #{e.message}")
      render :new, status: :unprocessable_entity
    end

    def join
      code = params[:code].to_s.strip
      @workspace = Workspace.find_by_join_code(code)

      # Invalid code - show error
      unless @workspace
        flash[:alert] = "Invalid or expired join code."
        redirect_to signed_in? ? workspaces_path : new_session_path
        return
      end

      # Redirect to workspace-scoped join URL - reuses UsersController with nametag UI
      redirect_to "/#{@workspace.external_id}/join/#{code}"
    end
  end
end
