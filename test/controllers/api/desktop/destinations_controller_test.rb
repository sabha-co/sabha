require "test_helper"

class API::Desktop::DestinationsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "once.sabha.test" }

  test "returns one branded destination with cable discovery path when signed in" do
    sign_in :david

    get "/api/desktop/destinations", headers: desktop_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["protocol_major"]
    assert_equal 1, body["destinations"].length

    destination = body["destinations"].first
    assert_equal "default", destination["id"]
    assert_equal Account.sole.name, destination["name"]
    assert_equal "/", destination["base_path"]
    assert_equal "/api/cable", destination["cable_path"]
  end

  test "is unauthorized without a session" do
    get "/api/desktop/destinations", headers: desktop_headers

    assert_response :unauthorized
    refute JSON.parse(response.body).key?("destinations")
  end

  private
    def desktop_headers
      { "Sabha-Desktop-Protocol-Major" => "1" }
    end
end
