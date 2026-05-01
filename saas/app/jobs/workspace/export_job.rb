# frozen_string_literal: true

class Workspace
  class ExportJob < ApplicationJob
    queue_as :default

    # Grace window past the presigned URL TTL — guarantees we don't yank the
    # artifact out from under a user who clicked their link near the deadline.
    PURGE_GRACE = 1.hour

    # The controller checks Workspace::R2.configured? before enqueuing so the
    # admin gets a flash for misconfig. Beyond that, this job intentionally
    # does NOT re-check — if an operator unsets R2 between enqueue and
    # perform, we want the failure to be loud (raise + retry/log) rather
    # than silently swallowed, leaving the admin waiting for an email that
    # will never arrive.
    def perform(workspace, recipient_email)
      export = Workspace::Export.create_from_database!(workspace)

      # Schedule cleanup before the email so a deliver_now failure still
      # leaves the artifact set to expire. On retry the upload creates a new
      # key; each orphan gets its own purge.
      Workspace::PurgeExportJob.set(wait: Workspace::Export::DEFAULT_URL_TTL + PURGE_GRACE)
        .perform_later(export.key)

      WorkspaceMailer.export_ready(workspace, recipient_email, export).deliver_now
    end
  end
end
