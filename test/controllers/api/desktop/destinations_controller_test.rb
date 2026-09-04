require "test_helper"

class API::Desktop::DestinationsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "once.sabha.test" }

  test "returns one branded destination with cable discovery path when signed in" do
    sign_in :david

    get "/api/desktop/destinations", headers: desktop_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["protocol_major"]
    assert_equal 1, body["peers"].length

    peer = body["peers"].first
    assert_equal "default", peer["id"]
    assert_equal Account.sole.name, peer["name"]
    assert peer["workspace_url"].end_with?("/")
    assert peer["cable_url"].end_with?("/api/cable")
  end

  test "is unauthorized without a session" do
    get "/api/desktop/destinations", headers: desktop_headers

    assert_response :unauthorized
    refute JSON.parse(response.body).key?("peers")
  end

  private
    def desktop_headers
      { "Sabha-Desktop-Protocol-Major" => "1" }
    end
end
