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
      tenant_id = workspace.external_id.to_s
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      filename = [ key_prefix, "#{timestamp}-#{SecureRandom.hex(4)}" ].compact.join("-")
      r2_key = "backups/#{workspace.external_id}/#{filename}.sqlite3"

      ApplicationRecord.with_tenant(tenant_id) do
        ApplicationRecord.connection.execute("PRAGMA wal_checkpoint(PASSIVE)")
      end

      source_path = Rails.root.join("storage/workspaces/#{Rails.env}/#{tenant_id}/db/main.sqlite3")
      Tempfile.create([ "backup", ".sqlite3" ]) do |tempfile|
        source_db = SQLite3::Database.new(source_path.to_s)
        dest_db = SQLite3::Database.new(tempfile.path)

        sqlite_backup = SQLite3::Backup.new(dest_db, "main", source_db, "main")
        sqlite_backup.step(-1)
        sqlite_backup.finish

        source_db.close
        dest_db.close

        tempfile.rewind
        s3_client.put_object(bucket: bucket, key: r2_key, body: tempfile)

        workspace.backups.create!(key: r2_key, size: tempfile.size)
      end
    end

    def download_to(path)
      s3_client.get_object(bucket: bucket, key: key, response_target: path)
    end

    def purge!
      s3_client.delete_object(bucket: bucket, key: key)
      destroy!
    rescue Aws::S3::Errors::NoSuchKey
      destroy!
    end

    private

      def s3_client
        self.class.s3_client
      end

      def bucket
        self.class.bucket
      end

      class << self
        def r2_configured?
          ENV["R2_ACCESS_KEY_ID"].present?
        end

        def s3_client
          @s3_client ||= Aws::S3::Client.new(
            access_key_id: ENV["R2_ACCESS_KEY_ID"],
            secret_access_key: ENV["R2_SECRET_ACCESS_KEY"],
            endpoint: ENV["R2_ENDPOINT"],
            region: "auto",
            force_path_style: true
          )
        end

        def bucket
          ENV.fetch("R2_BUCKET", "sabha-backups")
        end
      end
  end
end
