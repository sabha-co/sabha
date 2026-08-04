module User::Avatar
  extend ActiveSupport::Concern

  ALLOWED_AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  included do
    has_one_attached :avatar do |attachable|
      attachable.variant :square, resize_to_limit: [ 512, 512 ], format: :webp
    end

    validate :avatar_content_type_allowed, if: :avatar_attached?
  end

  class_methods do
    def from_avatar_token(sid)
      find_signed!(sid, purpose: :avatar)
    end
  end

  def avatar_token
    signed_id(purpose: :avatar)
  end

  # nil when the avatar can't be resized, so callers fall back to a generated one. libvips refuses
  # formats whose only loader is unfuzzed, and it chooses that loader from the file's actual bytes —
  # which need not match the content type declared on upload.
  def avatar_variant
    return unless avatar.attached? && avatar.variable?

    avatar.variant(:square).processed
  rescue Vips::Error => error
    Rails.logger.warn "Could not resize avatar for user #{id}: #{error.message}"
    nil
  end

  private
    def avatar_attached?
      avatar.attached?
    end

    def avatar_content_type_allowed
      unless ALLOWED_AVATAR_CONTENT_TYPES.include?(avatar.content_type)
        errors.add(:avatar, "must be a JPEG, PNG, GIF, or WebP image")
      end
    end
end
