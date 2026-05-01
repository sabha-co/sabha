# frozen_string_literal: true

class Workspace
  class PurgeExportJob < ApplicationJob
    queue_as :default

    # Delete an export artifact from R2. Scheduled by Workspace::ExportJob to
    # fire shortly after the presigned download URL expires, so each export
    # cleans itself up. NoSuchKey is benign — the object may already be gone
    # because of an earlier purge or operator-side cleanup.
    def perform(key)
      Workspace::R2.client.delete_object(bucket: Workspace::R2.bucket, key: key)
    rescue Aws::S3::Errors::NoSuchKey
      # already gone
    end
  end
end
