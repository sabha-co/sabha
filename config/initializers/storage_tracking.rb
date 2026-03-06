Rails.application.config.to_prepare do
  ActiveStorage::Attachment.include Storage::AttachmentTracking
end
