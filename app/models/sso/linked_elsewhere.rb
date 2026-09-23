# A member tried to connect a sabha.co account that already signs in to a
# different account here.
class Sso::LinkedElsewhere < Sso::Forbidden
  def initialize(message = "sabha.co identity is linked to another user.")
    super(
      message,
      user_message: "That sabha.co account is already connected to a different account here.",
      status: :forbidden
    )
  end
end
