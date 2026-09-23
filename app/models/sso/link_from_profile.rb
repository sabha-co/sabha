# sabha.co vouched for an email that already has an account here, but that
# account hasn't connected sabha.co. Emails never merge accounts; the owner
# connects it from their profile after signing in the usual way.
class Sso::LinkFromProfile < Sso::Forbidden
  def initialize(message = "sabha.co identity matches an unlinked account by email.")
    super(
      message,
      user_message: "You already have an account here. Sign in the usual way, then connect sabha.co from your profile.",
      status: :forbidden
    )
  end
end
