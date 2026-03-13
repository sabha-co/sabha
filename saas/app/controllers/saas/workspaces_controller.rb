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

    def create
      workspace = Workspace.create_with_database!(
        name: params[:name],
        creator: current_global_identity
      )

      redirect_to "/#{workspace.external_id}/invite", notice: "Workspace created!"
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
  end
end
