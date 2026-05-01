# frozen_string_literal: true

class Workspace
  class BackupJob < ApplicationJob
    queue_as :default

    # The controller and the daily cron both gate on Workspace::R2.configured?
    # so this job assumes R2 is set up. If an operator unsets R2 between
    # enqueue and perform, we want the failure loud (raise + log) rather than
    # silently dropped — symmetric with Workspace::ExportJob.
    def perform(workspace)
      Workspace::Backup.create_from_database!(workspace)
      workspace.backups.expired.find_each(&:purge!)
    end
  end
end
