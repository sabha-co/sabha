module EmailValidation
  extend ActiveSupport::Concern

  private
    def valid_email?(email)
      email.present? && email.is_a?(String) && email.match?(URI::MailTo::EMAIL_REGEXP)
    end

    def render_invalid_email
      head :unprocessable_entity
    end
end
