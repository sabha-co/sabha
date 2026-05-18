module Sso
  class UserResolver
    Result = Data.define(:user, :session_allowed, :activation_required, :failure, :message) do
      alias_method :session_allowed?, :session_allowed
      alias_method :activation_required?, :activation_required
      alias_method :failure?, :failure
    end

    LOCKS = Hash.new { |locks, external_id| locks[external_id] = Mutex.new }
    LOCKS_MUTEX = Mutex.new

    def self.resolve(payload)
      new(payload).resolve
    end

    def initialize(payload)
      @payload = payload
    end

    def resolve
      return failure("SSO response is missing an external id.") if external_id.blank?
      return failure("SSO response is missing an email address.") if email_address.blank?

      with_external_id_lock do
        User.transaction do
          resolve_by_external_id || resolve_by_email || create_user
        end
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      Rails.logger.warn("[SSO] Failed to resolve user for external_id=#{external_id.inspect}: #{error.message}")
      failure("Unable to sign in with SSO.")
    end

    private
      attr_reader :payload

      def resolve_by_external_id
        return unless record = SingleSignOnRecord.find_by(external_id: external_id)

        user = record.user
        update_record!(record)
        update_profile!(user)
        activation_required_result(user)
      end

      def resolve_by_email
        user = User.active.find_by(email_address: email_address)
        return unless user

        if activation_required?
          Rails.logger.warn("[SSO] Refused to claim existing email with require_activation=true: email=#{email_address.inspect} external_id=#{external_id.inspect}")
          return failure("Please verify your email address before signing in with SSO.")
        end

        if user.single_sign_on_record.present?
          Rails.logger.warn("[SSO] Refused email takeover: email=#{email_address.inspect} external_id=#{external_id.inspect} existing_external_id=#{user.single_sign_on_record.external_id.inspect}")
          return failure("Unable to sign in with SSO.")
        end

        user.create_single_sign_on_record!(
          external_id: external_id,
          external_email: email_address,
          last_payload: audit_payload,
          last_seen_at: Time.current
        )
        update_profile!(user)
        success(user)
      end

      def create_user
        user = User.create!(
          name: name,
          email_address: email_address,
          avatar_url: avatar_url,
          verified_at: activation_required? ? nil : Time.current
        )

        user.create_single_sign_on_record!(
          external_id: external_id,
          external_email: email_address,
          last_payload: audit_payload,
          last_seen_at: Time.current
        )

        activation_required_result(user)
      end

      def update_record!(record)
        record.update!(
          external_email: email_address,
          last_payload: audit_payload,
          last_seen_at: Time.current
        )
      end

      def update_profile!(user)
        attributes = {}
        attributes[:name] = name if overrides_name? && payload["name"].present?
        attributes[:avatar_url] = avatar_url if overrides_avatar? && avatar_url.present?
        user.update!(attributes) if attributes.any?
      end

      def activation_required_result(user)
        if activation_required? && !user.verified?
          user.send_verification_email
          Result.new(user:, session_allowed: false, activation_required: true, failure: false, message: "Please verify your email address before signing in.")
        else
          success(user)
        end
      end

      def success(user)
        Result.new(user:, session_allowed: true, activation_required: false, failure: false, message: nil)
      end

      def failure(message)
        Result.new(user: nil, session_allowed: false, activation_required: false, failure: true, message:)
      end

      def with_external_id_lock(&block)
        mutex = LOCKS_MUTEX.synchronize { LOCKS[external_id] }
        mutex.synchronize(&block)
      end

      def external_id
        payload["external_id"].to_s
      end

      def email_address
        payload["email"].to_s.downcase
      end

      def name
        candidate = payload["name"].presence || email_address.split("@").first
        candidate.to_s.length >= 2 ? candidate : User::DEFAULT_NAME
      end

      def avatar_url
        payload["avatar_url"]
      end

      def activation_required?
        payload["require_activation"] == true
      end

      def overrides_name?
        ENV["SSO_OVERRIDES_NAME"] == "true"
      end

      def overrides_avatar?
        ENV["SSO_OVERRIDES_AVATAR"] == "true"
      end

      def audit_payload
        payload.to_json
      end
  end
end
