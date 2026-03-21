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

      backup.download_to(staging_path)

      # Swap the database file
      File.rename(db_path, old_path) if File.exist?(db_path)
      File.rename(staging_path, db_path)

      # Remove WAL/SHM from both old and new paths
      FileUtils.rm_f("#{db_path}-wal")
      FileUtils.rm_f("#{db_path}-shm")
      FileUtils.rm_f(old_path)
      FileUtils.rm_f("#{old_path}-wal")
      FileUtils.rm_f("#{old_path}-shm")

      # Drop the tenant connection pool in this process so subsequent queries
      # connect to the new database file.
      #
      # NOTE: This only affects the current process. Other processes (web,
      # AnyCable) retain open file descriptors to the old inode until their
      # connection pools are reaped or the process restarts. In production,
      # the max_connection_pools LRU reaper handles this — idle tenant pools
      # are evicted and reconnect to the new file on next access. For
      # immediate consistency across all processes, restart the web container
      # after a restore.
      ApplicationRecord.with_tenant(tenant_id, prohibit_shard_swapping: false) do
        ApplicationRecord.remove_connection
      end
    ensure
      FileUtils.rm_f(staging_path) if staging_path && File.exist?(staging_path)
    end
  end
end
