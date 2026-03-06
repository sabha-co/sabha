module Account::Storage
  extend ActiveSupport::Concern
  include Storage::Totaled

  def exceeding_storage_limit?
    bytes_used > Storage::WORKSPACE_LIMIT
  end

  def nearing_storage_limit?
    bytes_used > Storage::WORKSPACE_LIMIT - 100.megabytes
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
      rich_text_ids = ActionText::RichText.where(record_type: "Message").ids
      return 0 if rich_text_ids.empty?

      ActiveStorage::Attachment
        .where(record_type: "ActionText::RichText", name: "embeds", record_id: rich_text_ids)
        .joins(:blob).sum("active_storage_blobs.byte_size")
    end
end
