module Message::Attachment
  extend ActiveSupport::Concern

  THUMBNAIL_MAX_WIDTH = 1200
  THUMBNAIL_MAX_HEIGHT = 800

  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg image/png image/gif image/webp
    video/mp4 video/quicktime video/webm
    audio/mpeg audio/mp4 audio/ogg audio/webm
    application/pdf
    text/plain text/csv
    application/zip
  ].freeze

  MAX_ATTACHMENT_SIZE = 50.megabytes

  included do
    has_one_attached :attachment do |attachable|
      attachable.variant :thumb, resize_to_limit: [ THUMBNAIL_MAX_WIDTH, THUMBNAIL_MAX_HEIGHT ]
    end

    validate :acceptable_attachment, if: :attachment?
    validate :within_storage_limit, on: :create, if: -> { Sabha.saas? && attachment? }
  end

  module ClassMethods
    def create_with_attachment!(attributes)
      create!(attributes).tap(&:process_attachment)
    end

    def create_with_attachment(attributes)
      create(attributes).tap(&:process_attachment)
    end
  end

  def attachment?
    attachment.attached?
  end

  def process_attachment
    ensure_attachment_analyzed
    process_attachment_thumbnail
  end

  private
    def acceptable_attachment
      unless ALLOWED_CONTENT_TYPES.include?(attachment.content_type)
        errors.add(:attachment, "type is not allowed")
      end

      if attachment.blob.byte_size > MAX_ATTACHMENT_SIZE
        errors.add(:attachment, "is too large (max #{MAX_ATTACHMENT_SIZE / 1.megabyte}MB)")
      end
    end

    def within_storage_limit
      if Current.account&.exceeding_storage_limit?
        errors.add(:attachment, "cannot be uploaded — workspace storage limit reached")
      end
    end

    def ensure_attachment_analyzed
      attachment&.analyze
    end

    def process_attachment_thumbnail
      case
      when attachment.video?
        attachment.preview(format: :webp).processed
      when attachment.representable?
        attachment.representation(:thumb).processed
      end
    end
end
