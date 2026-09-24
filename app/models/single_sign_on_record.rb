class SingleSignOnRecord < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: { scope: :issuer }

  scope :issued_by, ->(provider) { where(issuer: provider.issuer) }

  # The account a provider's payload signs in to. The workspace's own single
  # sign-on keeps its long-standing rules, including claiming an existing
  # account by email. sabha.co never matches by email: an account connects it
  # from the profile, and new accounts need an invite unless the admin opens
  # sign-up to it.
  def self.find_or_provision!(payload, provider: Sso::Provider.custom, invited: false)
    raise Sso::Forbidden, "SSO response is missing an external id." if external_id_from(payload).blank?
    raise Sso::Forbidden, "SSO response is missing an email address." if email_address_from(payload).blank?

    transaction do
      if provider.hub?
        find_or_provision_for_hub!(payload, provider, invited:)
      else
        find_for_custom(payload, provider)&.apply_sso!(payload) ||
          claim_existing_user!(payload, provider) ||
          provision_user!(payload, provider)
      end
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    Rails.logger.warn("[SSO] Failed to resolve user for external_id=#{external_id_from(payload).inspect}: #{error.message}")
    raise Sso::Forbidden, "Unable to sign in with SSO."
  end

  # A signed-in member connecting a provider they asked to connect. The
  # provider's email may differ from theirs: the request is the proof, not the
  # address.
  def self.link!(user, payload, provider:)
    raise Sso::Forbidden, "SSO response is missing an external id." if external_id_from(payload).blank?
    raise Sso::ActivationRequired if activation_required?(payload)

    record = issued_by(provider).find_or_initialize_by(external_id: external_id_from(payload))
    raise Sso::LinkedElsewhere unless record.new_record? || record.user == user

    record.update!(user:, external_email: email_address_from(payload), last_payload: payload.to_json, last_seen_at: Time.current)
    record
  rescue ActiveRecord::RecordNotUnique
    raise Sso::LinkedElsewhere
  end

  def seen!(payload)
    update!(
      external_email: payload["email"].to_s.downcase,
      last_payload: payload.to_json,
      last_seen_at: Time.current
    )
  end

  # sabha.co's profile is a hint at sign-up, never an override afterwards
  def apply_sso!(payload, provider = Sso::Provider.custom)
    raise Sso::Forbidden, "Unable to sign in with SSO." unless user.active?

    seen!(payload)
    update_user_profile!(payload) unless provider.hub?
    self
  end

  def require_activation!(payload)
    if self.class.activation_required?(payload) && !user.verified?
      user.send_verification_email
      raise Sso::ActivationRequired
    end
  end

  def update_user_profile!(payload)
    attributes = {}
    attributes[:name] = self.class.name_from(payload) if overrides_name? && payload["name"].present?
    attributes[:avatar_url] = payload["avatar_url"] if overrides_avatar? && payload["avatar_url"].present?
    user.update!(attributes) if attributes.any?
  end

  def self.external_id_from(payload)
    payload["external_id"].to_s
  end

  def self.email_address_from(payload)
    payload["email"].to_s.downcase
  end

  def self.name_from(payload)
    candidate = payload["name"].presence || email_address_from(payload).split("@").first
    candidate.to_s.length >= 2 ? candidate : User::DEFAULT_NAME
  end

  def self.activation_required?(payload)
    payload["require_activation"] == true
  end

  private
    # Rows from before links were keyed by issuer belong to the custom
    # provider; the first callback that presents one stamps it.
    def self.find_for_custom(payload, provider)
      issued_by(provider).find_by(external_id: external_id_from(payload)) ||
        where(issuer: nil).find_by(external_id: external_id_from(payload))&.tap { it.update!(issuer: provider.issuer) }
    end

    def self.find_or_provision_for_hub!(payload, provider, invited:)
      raise Sso::ActivationRequired if activation_required?(payload)

      if (record = issued_by(provider).find_by(external_id: external_id_from(payload)))
        record.apply_sso!(payload, provider)
      elsif User.exists?(email_address: email_address_from(payload))
        raise Sso::ProfileLinkRequired
      elsif invited || provider.auto_provision?
        provision_user!(payload, provider)
      else
        raise Sso::InviteRequired
      end
    end

    def self.claim_existing_user!(payload, provider)
      user = User.active.find_by(email_address: email_address_from(payload))
      return unless user

      if activation_required?(payload)
        Rails.logger.warn("[SSO] Refused to claim existing email with require_activation=true: email=#{email_address_from(payload).inspect} external_id=#{external_id_from(payload).inspect}")
        raise Sso::ActivationRequired
      end

      if (existing = user.single_sign_on_records.where(issuer: [ provider.issuer, nil ]).first)
        Rails.logger.warn("[SSO] Refused email takeover: email=#{email_address_from(payload).inspect} " \
          "incoming_external_id=#{external_id_from(payload).inspect} " \
          "existing_external_id=#{existing.external_id.inspect} user=#{user.id}")
        raise Sso::AlreadyLinked
      end

      user.single_sign_on_records.create!(
        issuer: provider.issuer,
        external_id: external_id_from(payload),
        external_email: email_address_from(payload),
        last_payload: payload.to_json,
        last_seen_at: Time.current
      ).tap do |record|
        record.update_user_profile!(payload)
      end
    end

    def self.provision_user!(payload, provider)
      user = User.create!(
        name: name_from(payload),
        email_address: email_address_from(payload),
        avatar_url: payload["avatar_url"],
        verified_at: activation_required?(payload) ? nil : Time.current
      )

      user.single_sign_on_records.create!(
        issuer: provider.issuer,
        external_id: external_id_from(payload),
        external_email: email_address_from(payload),
        last_payload: payload.to_json,
        last_seen_at: Time.current
      )
    end

    def overrides_name?
      ENV["SSO_OVERRIDES_NAME"] == "true"
    end

    def overrides_avatar?
      ENV["SSO_OVERRIDES_AVATAR"] == "true"
    end
end
