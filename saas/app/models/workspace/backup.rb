# frozen_string_literal: true

class Workspace
  class Backup < UntenantedRecord
    self.table_name = "workspace_backups"

    RETENTION_PERIOD = 7.days

    belongs_to :workspace, optional: true

    scope :expired, -> { where(created_at: ...RETENTION_PERIOD.ago) }

    def self.purge_expired!
      expired.find_each do |backup|
        backup.purge!
      end
    end

    def self.create_from_database!(workspace, key_prefix: nil)
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      filename = [ key_prefix, "#{timestamp}-#{SecureRandom.hex(4)}" ].compact.join("-")
      r2_key = "backups/#{workspace.external_id}/#{filename}.sqlite3"

      Tempfile.create([ "backup", ".sqlite3" ]) do |tempfile|
        workspace.snapshot_database_to(tempfile.path)

        tempfile.rewind
        Workspace::R2.client.put_object(bucket: Workspace::R2.bucket, key: r2_key, body: tempfile)

        workspace.backups.create!(key: r2_key, size: tempfile.size)
      end
    end

    def download_to(path)
      Workspace::R2.client.get_object(bucket: Workspace::R2.bucket, key: key, response_target: path)
    end

    def purge!
      Workspace::R2.client.delete_object(bucket: Workspace::R2.bucket, key: key)
      destroy!
    rescue Aws::S3::Errors::NoSuchKey
      destroy!
    end
  end
end
