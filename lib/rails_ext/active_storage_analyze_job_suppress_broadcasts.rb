# Suppress Turbo broadcasts during Active Storage blob analysis.
#
# When Active Storage analyzes a blob (extracts dimensions, duration, etc.),
# it touches the associated record, which triggers Turbo broadcasts. This
# causes spurious page refreshes during upload.
#
# A better option would be to disable touching with +touch_attachment_records+
# but there is currently a bug: https://github.com/rails/rails/issues/55144
module ActiveStorageAnalyzeJobSuppressBroadcasts
  def perform(blob)
    Message.suppressing_turbo_broadcasts do
      super
    end
  end
end

ActiveSupport.on_load :active_storage_blob do
  ActiveStorage::AnalyzeJob.prepend ActiveStorageAnalyzeJobSuppressBroadcasts
end
