class Sso::Failed < Sso::Error
  def initialize(message = "The SSO provider rejected the sign-in.")
    super(message, user_message: "Single sign-on failed.")
  end
end
