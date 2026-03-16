# frozen_string_literal: true

class WorkspaceMailer < ApplicationMailer
  def welcome(workspace)
    @workspace = workspace
    @creator = workspace.creator
    @workspace_url = "#{Branding.app_url}/#{workspace.external_id}"
    @invite_url = "#{@workspace_url}/invite"

    mail(
      to: @creator.email_address,
      subject: "Your workspace \"#{workspace.name}\" is ready"
    )
  end
end
