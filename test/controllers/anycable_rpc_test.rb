require "test_helper"

class AnycableRpcTest < ActionDispatch::IntegrationTest
  test "HTTP RPC endpoint is mounted at /_anycable" do
    post "/_anycable/connect", as: :json

    # Endpoint is mounted and rejects unauthenticated requests; absence of mount
    # would surface as 404 (or a routing exception in test env). 401 confirms
    # the endpoint is wired and the RPC auth check is in front of it.
    assert_response :unauthorized
  end
end
