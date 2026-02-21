module User::Avatar
  extend ActiveSupport::Concern

  ALLOWED_AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  included do
    has_one_attached :avatar

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
