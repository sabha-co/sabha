# frozen_string_literal: true

class Workspace
  class Backup < UntenantedRecord
    self.table_name = "workspace_backups"

    RETENTION_PERIOD = 7.days

    belongs_to :workspace

    scope :expired, -> { where(created_at: ...RETENTION_PERIOD.ago) }

    def self.purge_expired!
      expired.find_each do |backup|
        backup.purge!
      end
    end

    def purge!
      s3_client.delete_object(bucket: bucket, key: key)
      destroy!
    rescue Aws::S3::Errors::NoSuchKey
      destroy!
    end

    def size_in_mb
      (size / 1_048_576.0).round(1)
    end

    private

      def s3_client
        self.class.s3_client
      end

      def bucket
        self.class.bucket
      end

      class << self
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
