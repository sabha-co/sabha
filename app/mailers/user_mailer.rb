class UserMailer < ApplicationMailer
  default from: -> { BrandingConfig.mailer_from }

  def email_verification(user)
    @user = user
    @verification_url = verify_email_url(token: user.generate_token_for(:email_verification))

    mail(to: user.email_address, subject: "Verify your email for #{BrandingConfig.app_name}")
  end

  def password_reset(user)
    @user = user
    @reset_url = edit_password_reset_url(token: user.generate_token_for(:password_reset))

    mail(to: user.email_address, subject: "Reset your password for #{BrandingConfig.app_name}")
  end
end
