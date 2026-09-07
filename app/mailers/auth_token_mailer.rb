class AuthTokenMailer < ApplicationMailer
  def otp(auth_token, automated: false)
    @otp_code = auth_token.code
    mark_automated_client(automated)

    mail(to: auth_token.user.email_address, subject: "Your sign-in code for #{Branding.contextual_app_name}")
  end
end
