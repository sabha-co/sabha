# frozen_string_literal: true

class Workspace
  # Shared R2 client config for workspace artifacts (backups, exports).
  # Both Workspace::Backup and Workspace::Export use this — keeps the env
  # plumbing in one place and avoids siblings reaching across each other
  # for infrastructure.
  module R2
    class << self
      # All three credentials must be set. Without any one of them
      # Aws::S3::Client.new will succeed but the first put/get/delete will fail
      # — and for the export flow that means we'd tell an admin "we'll email
      # you a link" before silently failing in the background.
      def configured?
        ENV["R2_ACCESS_KEY_ID"].present? &&
          ENV["R2_SECRET_ACCESS_KEY"].present? &&
          ENV["R2_ENDPOINT"].present?
      end

      def client
        Aws::S3::Client.new(
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
