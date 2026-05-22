module User::EmailChangeable
  extend ActiveSupport::Concern

  included do
    validates :unconfirmed_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
    normalizes :unconfirmed_email, with: ->(email) { email&.strip&.downcase }

    generates_token_for :email_change, expires_in: 24.hours

    after_update :send_email_change_notification, if: :saved_change_to_email_address?
  end

  def update_email(new_email)
    return true if new_email.blank? || new_email.downcase == email_address

    if update(unconfirmed_email: new_email)
      send_email_reconfirmation
      true
    else
      false
    end
  end

  def send_email_reconfirmation
    return if bot?
    UserMailer.email_reconfirmation(self).deliver_later
  end

  def confirm_email_change!
    return unless unconfirmed_email.present?

    update!(email_address: unconfirmed_email, unconfirmed_email: nil)
  end

  def cancel_email_change!
    return unless unconfirmed_email.present?

    update!(unconfirmed_email: nil)
  end

  def pending_email_change?
    unconfirmed_email.present?
  end

  private
    def send_email_change_notification
      return if bot?
      old_email = email_address_before_last_save
      UserMailer.email_changed(self, old_email).deliver_later if old_email.present?
    end
end
