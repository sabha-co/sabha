class SingleSignOnRecord < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true

  def self.find_or_provision!(payload)
    raise User::SingleSignOnForbidden, "SSO response is missing an external id." if external_id_from(payload).blank?
    raise User::SingleSignOnForbidden, "SSO response is missing an email address." if email_address_from(payload).blank?

    transaction do
      find_by(external_id: external_id_from(payload))&.apply_sso!(payload) ||
        claim_existing_user!(payload) ||
        provision_user!(payload)
    end.tap do |record|
      record.require_activation!(payload)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    Rails.logger.warn("[SSO] Failed to resolve user for external_id=#{external_id_from(payload).inspect}: #{error.message}")
    raise User::SingleSignOnForbidden, "Unable to sign in with SSO."
  end

  def seen!(payload)
    update!(
      external_email: payload["email"].to_s.downcase,
      last_payload: payload.to_json,
      last_seen_at: Time.current
    )
  end

  def apply_sso!(payload)
    raise User::SingleSignOnForbidden, "Unable to sign in with SSO." unless user.active?

    seen!(payload)
    update_user_profile!(payload)
    self
  end

  def require_activation!(payload)
    if self.class.activation_required?(payload) && !user.verified?
      user.send_verification_email
      raise User::SingleSignOnActivationRequired
    end
  end

  def update_user_profile!(payload)
    attributes = {}
    attributes[:name] = self.class.name_from(payload) if overrides_name? && payload["name"].present?
    attributes[:avatar_url] = payload["avatar_url"] if overrides_avatar? && payload["avatar_url"].present?
    user.update!(attributes) if attributes.any?
  end

  private
    def self.claim_existing_user!(payload)
      user = User.active.find_by(email_address: email_address_from(payload))
      return unless user

      if activation_required?(payload)
        Rails.logger.warn("[SSO] Refused to claim existing email with require_activation=true: email=#{email_address_from(payload).inspect} external_id=#{external_id_from(payload).inspect}")
        raise User::SingleSignOnActivationRequired
      end

      if user.single_sign_on_record.present?
        Rails.logger.warn("[SSO] Refused email takeover: email=#{email_address_from(payload).inspect} external_id=#{external_id_from(payload).inspect} existing_external_id=#{user.single_sign_on_record.external_id.inspect}")
        raise User::SingleSignOnForbidden, "Unable to sign in with SSO."
      end

      user.create_single_sign_on_record!(
        external_id: external_id_from(payload),
        external_email: email_address_from(payload),
        last_payload: payload.to_json,
        last_seen_at: Time.current
      ).tap do |record|
        record.update_user_profile!(payload)
      end
    end

    def self.provision_user!(payload)
      user = User.create!(
        name: name_from(payload),
        email_address: email_address_from(payload),
        avatar_url: payload["avatar_url"],
        verified_at: activation_required?(payload) ? nil : Time.current
      )

      user.create_single_sign_on_record!(
        external_id: external_id_from(payload),
        external_email: email_address_from(payload),
        last_payload: payload.to_json,
        last_seen_at: Time.current
      )
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

    def overrides_name?
      ENV["SSO_OVERRIDES_NAME"] == "true"
    end

    def overrides_avatar?
      ENV["SSO_OVERRIDES_AVATAR"] == "true"
    end
end
