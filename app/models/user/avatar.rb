module User::Avatar
  extend ActiveSupport::Concern

  ALLOWED_AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  MAX_AVATAR_SIZE = 5.megabytes

  included do
    has_one_attached :avatar, dependent: :purge_later

    validate :acceptable_avatar, if: :avatar_attached?
  end

  class_methods do
    def from_avatar_token(sid)
      find_signed!(sid, purpose: :avatar)
    end
  end

  def avatar_token
    signed_id(purpose: :avatar)
  end

  private
    def avatar_attached?
      avatar.attached?
    end

    def acceptable_avatar
      unless ALLOWED_AVATAR_CONTENT_TYPES.include?(avatar.content_type)
        errors.add(:avatar, "must be a JPEG, PNG, GIF, or WebP image")
        return
      end

      if avatar.byte_size > MAX_AVATAR_SIZE
        errors.add(:avatar, "is too large (max #{MAX_AVATAR_SIZE / 1.megabyte}MB)")
      end
    end
end
