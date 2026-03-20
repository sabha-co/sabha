# frozen_string_literal: true

class Workspace
  class RestoreJob < ApplicationJob
    queue_as :default

    def perform(workspace, backup)
      tenant_id = workspace.external_id.to_s
      db_path = Rails.root.join("storage/workspaces/#{Rails.env}/#{tenant_id}/db/main.sqlite3")

      # Download backup from R2 to a local file in the same directory (for atomic rename)
      staging_path = "#{db_path}.restoring"

      Workspace::Backup.s3_client.get_object(
        bucket: Workspace::Backup.bucket,
        key: backup.key,
        response_target: staging_path
      )

      # Suspend the workspace to block new requests across all processes,
      # then disconnect this process's tenant connection pool
      workspace.suspend!

      ApplicationRecord.with_tenant(tenant_id) do
        ApplicationRecord.remove_connection
      end

      # Atomic swap — File.rename is atomic on the same filesystem
      File.rename(staging_path, db_path)
      FileUtils.rm_f("#{db_path}-wal")
      FileUtils.rm_f("#{db_path}-shm")

      workspace.unsuspend!
    ensure
      FileUtils.rm_f(staging_path) if staging_path && File.exist?(staging_path)
      workspace.unsuspend! if workspace.suspended?
    end
  end
end
