require "test_helper"

class API::ManifestsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "once.sabha.test" }

  test "returns protocol version 1 product identity and sign-in path without authentication" do
    get "/api/manifest", headers: protocol_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["protocol_major"]
    assert_equal Branding.app_name, body.dig("product", "name")
    assert_equal Branding.app_short_name, body.dig("product", "short_name")
    assert_equal Branding.app_short_name.to_s.parameterize.presence || "sabha", body.dig("product", "slug")
    assert_equal "/api/destinations", body["destinations_path"]
    assert_equal "/session/new", body["sign_in_path"]
    refute body.key?("destinations")
    refute body.key?("members")
    refute body.key?("multi_tenant")
  end

  test "describes the community with its name, address and no logo when none is set" do
    get "/api/manifest", headers: protocol_headers

    community = JSON.parse(response.body)["community"]
    assert_equal accounts(:signal).name, community["name"]
    assert_equal Branding.app_url, community["url"]
    assert_nil community["logo_url"]
  end

  test "points the community logo at the versioned small logo" do
    accounts(:signal).logo.attach io: file_fixture("moon.jpg").open, filename: "moon.jpg", content_type: "image/jpeg"

    get "/api/manifest", headers: protocol_headers

    logo_url = URI(JSON.parse(response.body).dig("community", "logo_url"))
    assert_equal "http://once.sabha.test/account/logo", "#{logo_url.scheme}://#{logo_url.host}#{logo_url.path}"
    assert_includes logo_url.query, "size=small"
    assert_includes logo_url.query, "v="
  end

  test "leaves the community out before first run" do
    Account.destroy_all

    get "/api/manifest", headers: protocol_headers

    assert_response :success
    refute JSON.parse(response.body).key?("community")
  end

  test "proves the sabha.co pairing only when a secret is set" do
    get "/api/manifest", headers: protocol_headers
    refute JSON.parse(response.body).key?("hub_proof")

    with_hub_secret("hub-secret") do
      get "/api/manifest", headers: protocol_headers
    end

    expected = OpenSSL::HMAC.hexdigest("sha256", "hub-secret", "sabha-hub-pairing:http://once.sabha.test")
    assert_equal expected, JSON.parse(response.body)["hub_proof"]
  end

  test "publishes no pairing proof beside the community's own single sign-on" do
    with_hub_secret("hub-secret") do
      Account.stubs(:sso_auth?).returns(true)
      get "/api/manifest", headers: protocol_headers
    end

    refute JSON.parse(response.body).key?("hub_proof")
  end

  test "refuses unsupported protocol majors with upgrade guidance" do
    get "/api/manifest", headers: { "Sabha-Protocol-Major" => "99" }

    assert_response :unsupported_media_type
    body = JSON.parse(response.body)
    assert_equal "unsupported_protocol_major", body["error"]
    assert_equal 1, body["supported_major"]
  end

  private
    def with_hub_secret(secret)
      original = ENV["SABHA_HUB_SECRET"]
      ENV["SABHA_HUB_SECRET"] = secret
      yield
    ensure
      original ? ENV["SABHA_HUB_SECRET"] = original : ENV.delete("SABHA_HUB_SECRET")
    end

    def protocol_headers
      { "Sabha-Protocol-Major" => "1" }
    end
end
