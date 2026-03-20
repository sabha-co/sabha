# frozen_string_literal: true

class Workspace
  class RestoreJob < ApplicationJob
    queue_as :default

    def perform(workspace, backup)
      tenant_id = workspace.external_id.to_s
      db_path = Rails.root.join("storage/workspaces/#{Rails.env}/#{tenant_id}/db/main.sqlite3")

      # Download backup to a staging file in the same directory (required for atomic rename)
      staging_path = "#{db_path}.restoring"
      old_path = "#{db_path}.old"

      Workspace::Backup.s3_client.get_object(
        bucket: Workspace::Backup.bucket,
        key: backup.key,
        response_target: staging_path
      )

      # Disconnect this process's tenant connection pool
      ApplicationRecord.with_tenant(tenant_id) do
        ApplicationRecord.remove_connection
      end

      # Atomic swap: move current DB aside, rename backup into place, clean up.
      # Other processes holding the old file will get SQLITE_IOERR on their next
      # query and re-establish a connection to the new file automatically.
      File.rename(db_path, old_path) if File.exist?(db_path)
      File.rename(staging_path, db_path)

      # Remove WAL/SHM from both old and new paths
      FileUtils.rm_f("#{db_path}-wal")
      FileUtils.rm_f("#{db_path}-shm")
      FileUtils.rm_f(old_path)
      FileUtils.rm_f("#{old_path}-wal")
      FileUtils.rm_f("#{old_path}-shm")
    ensure
      FileUtils.rm_f(staging_path) if staging_path && File.exist?(staging_path)
    end
  end
end
