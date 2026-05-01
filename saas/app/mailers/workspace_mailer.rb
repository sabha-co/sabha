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

  def export_ready(workspace, recipient_email, export)
    @workspace = workspace
    @download_url = export.signed_url
    @filename = export.filename
    @size = export.size
    @expires_in_hours = (Workspace::Export::DEFAULT_URL_TTL / 1.hour).to_i

    mail(
      to: recipient_email,
      subject: "Your \"#{workspace.name}\" export is ready",
      reply_to: Branding.support_email
    )
  end
end
