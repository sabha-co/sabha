# frozen_string_literal: true

class Workspace
  # Builds a sanitized, gzipped snapshot of a workspace's tenant SQLite,
  # uploads it to R2, and exposes a presigned download URL with a TTL.
  #
  # The artifact is intended for a workspace admin to take their data with them
  # to a self-hosted Sabha install. Workspace::Backup serves a different need
  # (operator-side cold archive for restores into the same SaaS instance) and
  # is intentionally kept separate.
  class Export
    DEFAULT_URL_TTL = 24.hours

    attr_reader :workspace, :key, :size

    def self.create_from_database!(workspace)
      new(workspace).tap(&:upload!)
    end

    def initialize(workspace)
      @workspace = workspace
      @key = build_key
    end

    def upload!
      Tempfile.create([ "workspace-export", ".sqlite3.gz" ]) do |gz_file|
        Tempfile.create([ "workspace-export-raw", ".sqlite3" ]) do |raw_file|
          workspace.export_for_self_host(raw_file.path)
          compress(raw_file.path, gz_file.path)
        end

        gz_file.rewind
        Workspace::R2.client.put_object(bucket: Workspace::R2.bucket, key: @key, body: gz_file)
        @size = gz_file.size
      end

      self
    end

    def signed_url(expires_in: DEFAULT_URL_TTL)
      Aws::S3::Presigner.new(client: Workspace::R2.client).presigned_url(
        :get_object, bucket: Workspace::R2.bucket, key: @key, expires_in: expires_in.to_i
      )
    end

    def filename
      File.basename(@key)
    end

    private
      def build_key
        timestamp = Time.current.strftime("%Y%m%d%H%M%S")
        "exports/#{workspace.external_id}/#{timestamp}-#{SecureRandom.hex(4)}.sqlite3.gz"
      end

      def compress(src, dst)
        Zlib::GzipWriter.open(dst) do |gz|
          File.open(src, "rb") { |raw| IO.copy_stream(raw, gz) }
        end
      end
  end
end
