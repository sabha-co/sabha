class UserMailer < ApplicationMailer
  def email_verification(user)
    @user = user
    @verification_url = verify_email_url(token: user.generate_token_for(:email_verification))

    mail(to: user.email_address, subject: "Verify your email for #{Branding.contextual_app_name}")
  end

  def password_reset(user)
    @user = user
    @reset_url = edit_password_reset_url(token: user.generate_token_for(:password_reset))

    mail(to: user.email_address, subject: "Reset your password for #{Branding.contextual_app_name}")
  end

  def email_reconfirmation(user)
    @user = user
    @confirmation_url = confirm_email_change_url(token: user.generate_token_for(:email_change))

    mail(to: user.unconfirmed_email, subject: "Confirm your new email address for #{Branding.contextual_app_name}")
  end

  def email_changed(user, old_email)
    @user = user
    @old_email = old_email

    mail(to: [ old_email, user.email_address ].compact.uniq, subject: "Your email address has been changed for #{Branding.contextual_app_name}")
  end

  def banned(user)
    @user = user
    @account_name = Account.sole&.name || Branding.contextual_app_name

    mail(to: user.email_address, subject: "Your access to #{@account_name} has been suspended")
  end

  def unbanned(user)
    @user = user
    @account_name = Account.sole&.name || Branding.contextual_app_name

    mail(to: user.email_address, subject: "Your access to #{@account_name} has been restored")
  end
end
