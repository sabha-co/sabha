class Sso::Error < StandardError
  attr_reader :user_message, :status

  def initialize(message = "Unable to sign in with SSO.", user_message: "Single sign-on failed.", status: :unauthorized)
    super(message)
    @user_message = user_message
    @status = status
  end
end
