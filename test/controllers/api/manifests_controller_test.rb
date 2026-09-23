require "test_helper"

class API::ManifestsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "once.sabha.test" }

  test "returns protocol version 1 product identity and sign-in path without authentication" do
    get "/api/manifest", headers: desktop_headers

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
  end

  test "refuses unsupported protocol majors with upgrade guidance" do
    get "/api/manifest", headers: { "Sabha-Protocol-Major" => "99" }

    assert_response :unsupported_media_type
    body = JSON.parse(response.body)
    assert_equal "unsupported_protocol_major", body["error"]
    assert_equal 1, body["supported_major"]
  end

  private
    def desktop_headers
      { "Sabha-Protocol-Major" => "1" }
    end
end
