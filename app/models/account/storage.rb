module Account::Storage
  extend ActiveSupport::Concern
  include Storage::Totaled

  def exceeding_storage_limit?
    bytes_used >= Storage::WORKSPACE_LIMIT
  end

  def nearing_storage_limit?
    bytes_used >= Storage::WORKSPACE_LIMIT - 100.megabytes
  end

  def storage_percentage_used
    [ (bytes_used.to_f / Storage::WORKSPACE_LIMIT * 100).round, 100 ].min
  end

  private
    def calculate_real_storage_bytes
      message_attachment_bytes + message_embed_bytes
    end

    def message_attachment_bytes
      ActiveStorage::Attachment
        .where(record_type: "Message", name: "attachment")
        .joins(:blob).sum("active_storage_blobs.byte_size")
    end

    def message_embed_bytes
      ActiveStorage::Attachment
        .where(record_type: "ActionText::RichText", name: "embeds")
        .where(record_id: ActionText::RichText.where(record_type: "Message").select(:id))
        .joins(:blob).sum("active_storage_blobs.byte_size")
    end
end
