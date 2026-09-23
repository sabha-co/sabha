# sabha.co vouched for someone new, and the community only lets people in by invite
class Sso::InviteRequired < Sso::Forbidden
  def initialize(message = "sabha.co sign-in for a new member without an invite.")
    super(
      message,
      user_message: "You need an invite to join #{Branding.contextual_app_name}. Ask a member for an invite link, then use it to sign in with sabha.co.",
      status: :forbidden
    )
  end
end
