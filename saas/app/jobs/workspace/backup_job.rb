# frozen_string_literal: true

class Workspace
  class BackupJob < ApplicationJob
    queue_as :default

    def perform(workspace)
      return unless Workspace::Backup.r2_configured?

      Workspace::Backup.create_from_database!(workspace)
      workspace.backups.expired.find_each(&:purge!)
    end
  end
end
