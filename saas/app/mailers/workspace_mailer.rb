# frozen_string_literal: true

class WorkspaceMailer < ApplicationMailer
  layout "mailer"

  def email_changed(global_identity, old_email, new_email)
    @identity = global_identity
    @old_email = old_email
    @new_email = new_email

    mail(
      to: [ old_email, new_email ].compact.uniq,
      subject: "Your email address has been changed for #{Branding.app_name}"
    )
  end

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

  def deleted(workspace_name, admin_email)
    @workspace_name = workspace_name

    mail(
      to: admin_email,
      subject: "Your workspace \"#{workspace_name}\" has been deleted",
      reply_to: Branding.support_email
    )
  end
end
