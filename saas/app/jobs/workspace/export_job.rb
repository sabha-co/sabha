# frozen_string_literal: true

class Workspace
  class ExportJob < ApplicationJob
    queue_as :default

    # The controller checks Workspace::R2.configured? before enqueuing so the
    # admin gets a flash for misconfig. Beyond that, this job intentionally
    # does NOT re-check — if an operator unsets R2 between enqueue and
    # perform, we want the failure to be loud (raise + retry/log) rather
    # than silently swallowed, leaving the admin waiting for an email that
    # will never arrive.
    #
    # Cleanup is delegated to an R2 bucket lifecycle rule on the `exports/`
    # prefix — operators configure objects there to expire ~2 days after
    # creation (24h URL TTL + grace). Each export carries a unique key, so
    # retries leave their own short-lived orphans for the same sweep.
    def perform(workspace, recipient_email)
      export = Workspace::Export.create_from_database!(workspace)
      WorkspaceMailer.export_ready(workspace, recipient_email, export).deliver_now
    end
  end
end
