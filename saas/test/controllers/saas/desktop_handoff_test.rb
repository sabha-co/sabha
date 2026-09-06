# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class DesktopHandoffTest < ActionDispatch::IntegrationTest
    setup do
      @original_clients = ENV["SSO_PROVIDER_CLIENTS"]
      @original_return_host = ENV["SSO_CLOUD_RETURN_HOST"]
      @original_return_path = ENV["SSO_CLOUD_RETURN_PATH"]
      @original_secret = ENV["SSO_CLOUD_SECRET"]

      ENV["SSO_PROVIDER_CLIENTS"] = "cloud"
      ENV["SSO_CLOUD_RETURN_HOST"] = "cloud.sabha.co"
      ENV["SSO_CLOUD_RETURN_PATH"] = "/session/sso/callback"
      ENV["SSO_CLOUD_SECRET"] = "cloud-sso-secret"
    end

    teardown do
      restore_env("SSO_PROVIDER_CLIENTS", @original_clients)
      restore_env("SSO_CLOUD_RETURN_HOST", @original_return_host)
      restore_env("SSO_CLOUD_RETURN_PATH", @original_return_path)
      restore_env("SSO_CLOUD_SECRET", @original_secret)
    end

    test "signed-in desktop handoff on session sso returns a one-time claim deep link" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)
      sso, sig = provider_request

      assert_difference -> { Desktop::GlobalSessionClaim.count }, 1 do
        get "/session/sso",
          params: {
            sso: sso,
            sig: sig,
            desktop_handoff: "1",
            desktop_nonce: "cloud-nonce",
            desktop_origin: "https://www.example.com",
            return_to: "/workspaces"
          }
      end

      assert_redirected_to %r{\Asabha://session-claim\?}
      claim = Desktop::GlobalSessionClaim.last
      assert_equal identity, claim.global_identity
      assert_equal "cloud-nonce", claim.nonce
      assert_equal "https://www.example.com", claim.origin
    end

    private
      def provider_request(attributes = {})
        Sso::Payload.encode({
          nonce: "provider-nonce",
          return_sso_url: "https://cloud.sabha.co/session/sso/callback"
        }.merge(attributes), ENV["SSO_CLOUD_SECRET"])
      end

      def restore_env(key, value)
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end
  end
end
