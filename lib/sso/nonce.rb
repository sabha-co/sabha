require "securerandom"

module Sso
  class Nonce
    class Error < StandardError; end
    class Invalid < Error; end
    class Replayed < Error; end

    ACTIVE_TTL = 30.minutes
    USED_TTL = 24.hours

    def self.issue(store, return_path:, now: Time.current)
      SecureRandom.hex.tap do |nonce|
        store[active_key(nonce)] = {
          "return_path" => return_path,
          "expires_at" => ACTIVE_TTL.from_now(now).to_i
        }
      end
    end

    def self.consume!(active_store:, used_store:, nonce:, now: Time.current)
      raise Replayed, "SSO nonce already used" if used_store[used_key(nonce)].present?

      key = active_key(nonce)
      entry = active_store[key]
      raise Invalid, "SSO nonce expired or invalid" if entry.blank?
      raise Invalid, "SSO nonce expired or invalid" if expired?(entry, now:)

      active_store.delete(key)
      used_store[used_key(nonce)] = {
        "used_at" => now.to_i,
        "expires_at" => USED_TTL.from_now(now).to_i
      }

      entry["return_path"]
    end

    def self.active_key(nonce)
      "sso_nonce_#{nonce}"
    end

    def self.used_key(nonce)
      "used_sso_nonce_#{nonce}"
    end

    def self.expired?(entry, now:)
      entry["expires_at"].to_i <= now.to_i
    end

    class CacheStore
      def initialize(cache, expires_in: USED_TTL)
        @cache = cache
        @expires_in = expires_in
      end

      def [](key)
        @cache.read(key)
      end

      def []=(key, value)
        @cache.write(key, value, expires_in: @expires_in)
      end

      def delete(key)
        @cache.delete(key)
      end
    end
  end
end
