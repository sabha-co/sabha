require "test_helper"

class API::Desktop::ManifestsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "once.sabha.test" }

  test "returns protocol version 1 product identity and sign-in path without authentication" do
    get "/api/desktop/manifest", headers: desktop_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["protocol_major"]
    assert_equal Branding.app_name, body.dig("product", "name")
    assert body["sign_in_path"].present?
    refute body.key?("destinations")
    refute body.key?("members")
  end

  test "refuses unsupported protocol majors with upgrade guidance" do
    get "/api/desktop/manifest", headers: { "Sabha-Desktop-Protocol-Major" => "99" }

    assert_response :unsupported_media_type
    body = JSON.parse(response.body)
    assert_equal "unsupported_protocol_major", body["error"]
    assert_equal 1, body["supported_major"]
    assert body["upgrade_url"].present?
  end

  private
    def desktop_headers
      { "Sabha-Desktop-Protocol-Major" => "1" }
    end
end
