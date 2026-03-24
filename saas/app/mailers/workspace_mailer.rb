# frozen_string_literal: true

class WorkspaceMailer < ApplicationMailer
  def welcome(workspace)
    @workspace = workspace
    @creator = workspace.creator
    @workspace_url = root_url(script_name: workspace.slug)
    @invite_url = invite_url(script_name: workspace.slug)

    mail(
      to: @creator.email_address,
      subject: "Your workspace \"#{workspace.name}\" is ready",
      reply_to: Branding.support_email
    )
  end
end
