module Storage::AttachmentTracking
  extend ActiveSupport::Concern

  included do
    before_destroy :snapshot_storage_context
    after_create_commit :record_storage_attach
    after_destroy_commit :record_storage_detach
  end

  private
    def record_storage_attach
      return unless storage_tracked_record

      Storage::Entry.record \
        recordable: storage_tracked_record,
        blob: blob,
        delta: blob.byte_size,
        operation: "attach"
    end

    def record_storage_detach
      return unless @storage_snapshot

      Storage::Entry.record \
        recordable: @storage_snapshot[:recordable],
        blob: blob,
        delta: -blob.byte_size,
        operation: "detach"
    end

    def snapshot_storage_context
      return unless storage_tracked_record

      @storage_snapshot = { recordable: storage_tracked_record }
    end

    def storage_tracked_record
      record.try(:storage_tracked_record)
    end
end
