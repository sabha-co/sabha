require "test_helper"

class API::CableControllerTest < ActionDispatch::IntegrationTest
  setup { host! "once.sabha.test" }

  test "returns the cable url and a verifiable identity token for a signed-in user" do
    sign_in :david

    get "/api/cable"

    assert_response :success
    body = JSON.parse(response.body)
    assert body["url"].present?, "expected a cable websocket url"
    assert_equal AnyCable.config.jwt_ttl, body["expires_in"]
    assert_equal users(:david), AnyCable::JWT.decode(body["token"])[:current_user]
  end

  test "is unauthorized without a session" do
    get "/api/cable"

    assert_response :unauthorized
    assert_not JSON.parse(response.body).key?("token")
  end
end
