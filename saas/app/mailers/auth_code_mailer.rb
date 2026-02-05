# frozen_string_literal: true

class AuthCodeMailer < ApplicationMailer
  # Sends OTP code for GlobalIdentity authentication (SaaS mode)
  #
  # Parallels AuthTokenMailer in self-hosted mode
  #
  # Used for sign-in, sign-up, and email change verification

  def code(auth_code)
    @auth_code = auth_code
    @code = auth_code.code
    @global_identity = auth_code.global_identity

    # Email change codes go to the NEW email to prove ownership
    recipient = if auth_code.email_change?
      @global_identity.unconfirmed_email
    else
      @global_identity.email_address
    end

    mail(
      to: recipient,
      subject: "Your verification code: #{@code}"
    )
  end
end
