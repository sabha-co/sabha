# "Continue with sabha.co" for an account that already exists here. Emails
# never link accounts; the member connects sabha.co from their own profile,
# signed in and recently checked.
module User::HubLinkable
  extend ActiveSupport::Concern

  class LastSignInMethodError < StandardError; end

  included do
    has_one :hub_link, -> { issued_by(Sso::Provider.hub) }, class_name: "SingleSignOnRecord"
  end

  def hub_linked?
    hub_link.present?
  end

  def link_hub!(payload)
    SingleSignOnRecord.link!(self, payload, provider: Sso::Provider.hub)
  end

  def unlink_hub!
    raise LastSignInMethodError unless signs_in_without_hub?

    hub_link&.destroy!
  end

  # Email codes always reach the member; a password workspace needs a password
  def signs_in_without_hub?
    Account.otp_auth? || password_digest.present?
  end
end
