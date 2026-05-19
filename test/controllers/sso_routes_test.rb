require "test_helper"

class SsoRoutesTest < ActionDispatch::IntegrationTest
  test "routes to sso init" do
    assert_routing({ method: :get, path: "/session/sso" }, controller: "sso/handshakes", action: "new")
    assert_routing({ method: :post, path: "/session/sso" }, controller: "sso/handshakes", action: "create")
  end

  test "routes to sso callback" do
    assert_routing "/session/sso/callback", controller: "sso/callbacks", action: "show"
  end
end
