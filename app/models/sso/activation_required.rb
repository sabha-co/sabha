class Sso::ActivationRequired < Sso::Error
  def initialize(message = "SSO email verification is required.")
    super(message, user_message: "Please verify your email address before signing in.")
  end
end
