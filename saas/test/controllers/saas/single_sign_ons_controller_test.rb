# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class SingleSignOnsControllerTest < ActionDispatch::IntegrationTest
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

    test "redirects unauthenticated users to global session login with the sso request as return_to" do
      sso, sig = provider_request

      get "/session/sso", params: { sso:, sig: }

      assert_redirected_to new_session_path(return_to: "/session/sso?sso=#{CGI.escape(sso)}&sig=#{sig}")
    end

    test "redirects back to registered client with signed global identity payload" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)
      sso, sig = provider_request

      get "/session/sso", params: { sso:, sig: }

      assert_response :redirect
      assert_match %r{\Ahttps://cloud\.sabha\.co/session/sso/callback\?}, response.location

      response_payload = callback_payload(response.location)
      assert_equal "cloud-nonce", response_payload["nonce"]
      assert_equal "global_identity:#{identity.id}", response_payload["external_id"]
      assert_equal identity.email_address, response_payload["email"]
      assert_equal identity.name, response_payload["name"]
      assert_equal false, response_payload["require_activation"]
    end

    test "requires activation for unverified global identities" do
      identity = global_identities(:unverified)
      sign_in_global_identity(identity)
      sso, sig = provider_request

      get "/session/sso", params: { sso:, sig: }

      response_payload = callback_payload(response.location)
      assert_equal true, response_payload["require_activation"]
    end

    test "rejects request with bad signature" do
      sso, = provider_request

      get "/session/sso", params: { sso:, sig: "bad-signature" }

      assert_response :forbidden
    end

    test "rejects request with missing payload" do
      get "/session/sso"

      assert_response :forbidden
    end

    test "rejects request without return url" do
      sso, sig = provider_request(return_sso_url: nil)

      get "/session/sso", params: { sso:, sig: }

      assert_response :forbidden
    end

    test "rejects unregistered return host" do
      sso, sig = provider_request(return_sso_url: "https://evil.example.com/session/sso/callback")

      get "/session/sso", params: { sso:, sig: }

      assert_response :forbidden
    end

    test "rejects unregistered return path" do
      sso, sig = provider_request(return_sso_url: "https://cloud.sabha.co/other/callback")

      get "/session/sso", params: { sso:, sig: }

      assert_response :forbidden
    end

    test "fails closed when no provider client is configured" do
      ENV.delete("SSO_PROVIDER_CLIENTS")
      sso, sig = provider_request

      get "/session/sso", params: { sso:, sig: }

      assert_response :service_unavailable
    end

    private
      def provider_request(attributes = {})
        Sso::Payload.encode({
          nonce: "cloud-nonce",
          return_sso_url: "https://cloud.sabha.co/session/sso/callback"
        }.merge(attributes), ENV["SSO_CLOUD_SECRET"])
      end

      def callback_payload(location)
        uri = URI.parse(location)
        query = Rack::Utils.parse_query(uri.query)

        Sso::Payload.decode(query["sso"], query["sig"], ENV["SSO_CLOUD_SECRET"])
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
