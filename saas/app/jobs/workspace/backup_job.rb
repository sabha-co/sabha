# frozen_string_literal: true

class Workspace
  class BackupJob < ApplicationJob
    queue_as :default

    def perform(workspace)
      tenant_id = workspace.external_id.to_s
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      key = "backups/#{workspace.external_id}/#{timestamp}.sqlite3"

      # Checkpoint WAL to flush as much data as possible to the main database file.
      # PASSIVE avoids blocking active readers/writers — the backup API handles the rest.
      ApplicationRecord.with_tenant(tenant_id) do
        ApplicationRecord.connection.execute("PRAGMA wal_checkpoint(PASSIVE)")
      end

      # Copy database using SQLite Online Backup API
      source_path = Rails.root.join("storage/workspaces/#{Rails.env}/#{tenant_id}/db/main.sqlite3")
      Tempfile.create([ "backup", ".sqlite3" ]) do |tempfile|
        source_db = SQLite3::Database.new(source_path.to_s)
        dest_db = SQLite3::Database.new(tempfile.path)

        backup = SQLite3::Backup.new(dest_db, "main", source_db, "main")
        backup.step(-1)
        backup.finish

        source_db.close
        dest_db.close

        # Upload to R2
        tempfile.rewind
        Workspace::Backup.s3_client.put_object(
          bucket: Workspace::Backup.bucket,
          key: key,
          body: tempfile
        )

        # Record backup
        workspace.backups.create!(
          key: key,
          size: tempfile.size
        )
      end

      # Clean up expired backups for this workspace
      workspace.backups.expired.find_each(&:purge!)
    end
  end
end
