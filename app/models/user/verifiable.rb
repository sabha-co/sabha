module User::Verifiable
  extend ActiveSupport::Concern

  included do
    scope :verified,   -> { where.not(verified_at: nil) }
    scope :unverified, -> { where(verified_at: nil) }

    generates_token_for :email_verification, expires_in: 24.hours

    after_create_commit :post_welcome_message
  end

  def verified?
    verified_at.present?
  end

  def verify_email!
    update!(verified_at: Time.current)
    post_welcome_message
  end

  def send_verification_email
    UserMailer.email_verification(self).deliver_later
  end

  private
    def post_welcome_message
      return unless bot? || verified?
      return unless room = Room.original

      room.post_welcome_message(user: self)
    end
end
