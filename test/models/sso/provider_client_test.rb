require "test_helper"

class Sso::ProviderClientTest < ActiveSupport::TestCase
  setup do
    @prior_env = ENV.to_h.dup
    ENV["SSO_PROVIDER_CLIENTS"] = "cloud_sabha,managed_sabha"
    ENV["SSO_CLOUD_SABHA_RETURN_HOST"]   = "cloud.sabha.co"
    ENV["SSO_CLOUD_SABHA_RETURN_PATH"]   = "/session/sso/callback"
    ENV["SSO_CLOUD_SABHA_SECRET"]        = "cloud-secret"
    ENV["SSO_MANAGED_SABHA_RETURN_HOST"] = "*.sabha.co"
    ENV["SSO_MANAGED_SABHA_RETURN_PATH"] = "/session/sso/callback"
    ENV["SSO_MANAGED_SABHA_SECRET"]      = "managed-secret"
  end

  teardown do
    ENV.replace(@prior_env)
  end

  test "exact-match client accepts its exact return URL" do
    assert cloud_sabha.verify_return_url!("https://cloud.sabha.co/session/sso/callback")
  end

  test "exact-match client rejects any other host" do
    assert_raises(Sso::ProviderClient::InvalidReturnUrl) do
      cloud_sabha.verify_return_url!("https://acme.sabha.co/session/sso/callback")
    end
  end

  test "wildcard client accepts a single-label subdomain" do
    assert managed_sabha.verify_return_url!("https://acme.sabha.co/session/sso/callback")
  end

  test "wildcard client rejects the bare base domain" do
    assert_raises(Sso::ProviderClient::InvalidReturnUrl) do
      managed_sabha.verify_return_url!("https://sabha.co/session/sso/callback")
    end
  end

  test "wildcard client rejects multi-label subdomains" do
    assert_raises(Sso::ProviderClient::InvalidReturnUrl) do
      managed_sabha.verify_return_url!("https://evil.acme.sabha.co/session/sso/callback")
    end
  end

  test "wildcard client rejects a different base domain" do
    assert_raises(Sso::ProviderClient::InvalidReturnUrl) do
      managed_sabha.verify_return_url!("https://acme.evil.com/session/sso/callback")
    end
  end

  test "wildcard client refuses a host claimed exactly by another configured client" do
    assert_raises(Sso::ProviderClient::InvalidReturnUrl) do
      managed_sabha.verify_return_url!("https://cloud.sabha.co/session/sso/callback")
    end
  end

  test "wildcard client still rejects wrong return path" do
    assert_raises(Sso::ProviderClient::InvalidReturnUrl) do
      managed_sabha.verify_return_url!("https://acme.sabha.co/admin/sso/callback")
    end
  end

  test "wildcard client rejects URL with userinfo" do
    assert_raises(Sso::ProviderClient::InvalidReturnUrl) do
      managed_sabha.verify_return_url!("https://attacker@acme.sabha.co/session/sso/callback")
    end
  end

  test "wildcard? reflects return_host" do
    assert managed_sabha.wildcard?
    assert_not cloud_sabha.wildcard?
  end

  test "authenticate picks the client whose secret matches and verifies its return URL" do
    encoded, sig = Sso::Payload.encode({
      nonce: "abc",
      return_sso_url: "https://acme.sabha.co/session/sso/callback"
    }, "managed-secret")

    client, payload = Sso::ProviderClient.authenticate(encoded, sig)

    assert_equal "managed_sabha", client.name
    assert_equal "abc", payload["nonce"]
  end

  test "authenticate rejects a managed_sabha-signed payload trying to return to cloud.sabha.co" do
    encoded, sig = Sso::Payload.encode({
      nonce: "abc",
      return_sso_url: "https://cloud.sabha.co/session/sso/callback"
    }, "managed-secret")

    assert_raises(Sso::ProviderClient::InvalidReturnUrl) do
      Sso::ProviderClient.authenticate(encoded, sig)
    end
  end

  private
    def cloud_sabha
      Sso::ProviderClient.active.find { |c| c.name == "cloud_sabha" }
    end

    def managed_sabha
      Sso::ProviderClient.active.find { |c| c.name == "managed_sabha" }
    end
end
