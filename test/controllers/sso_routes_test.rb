require "test_helper"

class SsoRoutesTest < ActionDispatch::IntegrationTest
  test "routes to sso init" do
    assert_routing "/session/sso", controller: "sso", action: "new"
  end

  test "routes to sso callback" do
    assert_routing "/session/sso/callback", controller: "sso", action: "show"
  end
end
