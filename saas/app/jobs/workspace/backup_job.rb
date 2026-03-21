# frozen_string_literal: true

class Workspace
  class BackupJob < ApplicationJob
    queue_as :default

    def perform(workspace)
      return unless ENV["R2_ACCESS_KEY_ID"].present?

      Workspace::Backup.create_from_database!(workspace)
      workspace.backups.expired.find_each(&:purge!)
    end
  end
end
