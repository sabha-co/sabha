# Raised when an SSO sign-in matches an existing account by email, but that
# account is already linked to a *different* external_id. Refusing is the
# account-takeover guard; this subclass exists only to give the failure a clear,
# actionable message and a correct 403 (the base Sso::Error defaults to 401).
class Sso::AlreadyLinked < Sso::Forbidden
  def initialize(message = "Email already linked to a different SSO identity.")
    super(
      message,
      user_message: "This account is already linked to a different sign-in. " \
                    "An admin must re-link it before you can sign in this way.",
      status: :forbidden
    )
  end
end
