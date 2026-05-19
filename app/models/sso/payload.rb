require "base64"
require "openssl"
require "rack/utils"

class Sso::Payload
  class Error < StandardError; end
  class InvalidSignature < Error; end
  class InvalidPayload < Error; end
  class BannedExternalId < Error; end

  ACCESSORS = %w[
    add_groups admin avatar_force_update avatar_url bio card_background_url
    confirmed_2fa email external_id failed groups locale locale_force_update
    location logout moderator name no_2fa_methods nonce prompt
    profile_background_url remove_groups require_2fa require_activation
    return_sso_url suppress_welcome_message title username website
  ].freeze

  BOOLS = %w[
    admin avatar_force_update confirmed_2fa failed locale_force_update logout
    moderator no_2fa_methods require_2fa require_activation
    suppress_welcome_message
  ].freeze

  BANNED_EXTERNAL_IDS = %w[none nil blank null].freeze
  BASE64_PATTERN = /\A[A-Za-z0-9=\r\n\/+]+\z/

  def self.encode(attributes, secret)
    unsigned_payload = Rack::Utils.build_query(attributes.compact)
    encoded_payload = Base64.strict_encode64(unsigned_payload)

    [ encoded_payload, sign(encoded_payload, secret) ]
  end

  def self.decode(encoded_payload, signature, secret)
    raise InvalidPayload, "Missing SSO payload" if encoded_payload.blank?
    raise InvalidPayload, "Invalid Base64 payload" unless encoded_payload.match?(BASE64_PATTERN)
    raise InvalidSignature, "Bad signature for payload" unless valid_signature?(encoded_payload, signature, secret)

    decoded_payload = Base64.decode64(encoded_payload)
    decoded_hash = Rack::Utils.parse_query(decoded_payload)
    parsed = parse_fields(decoded_hash)

    parsed["external_id"] = parsed["external_id"].to_s.downcase
    raise BannedExternalId, "Invalid external_id" if BANNED_EXTERNAL_IDS.include?(parsed["external_id"])

    parsed
  rescue ArgumentError
    raise InvalidPayload, "Invalid Base64 payload"
  end

  def self.sign(payload, secret)
    OpenSSL::HMAC.hexdigest("sha256", secret, payload)
  end

  def self.valid_signature?(payload, signature, secret)
    expected_signature = sign(payload, secret)
    return false unless signature.present? && signature.bytesize == expected_signature.bytesize

    ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
  end

  def self.parse_fields(decoded_hash)
    parsed = {}

    ACCESSORS.each do |field|
      value = decoded_hash[field]
      value = BOOLS.include?(field) ? parse_bool(value) : value
      parsed[field] = value unless value.nil?
    end

    custom_fields = decoded_hash.each_with_object({}) do |(key, value), fields|
      if (field = key[/\Acustom\.(.+)\z/, 1])
        fields[field] = value
      end
    end
    parsed["custom_fields"] = custom_fields if custom_fields.any?

    parsed
  end

  def self.parse_bool(value)
    %w[true false].include?(value) ? value == "true" : nil
  end
end
