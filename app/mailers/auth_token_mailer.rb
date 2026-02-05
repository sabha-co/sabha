class AuthTokenMailer < ApplicationMailer
  def otp(auth_token)
    @otp_code = auth_token.code

    mail(to: auth_token.user.email_address, subject: "Your sign-in code for #{Branding.contextual_app_name}")
  end
end
