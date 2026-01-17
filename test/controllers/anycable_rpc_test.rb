require "test_helper"

class AnycableRpcTest < ActionDispatch::IntegrationTest
  test "HTTP RPC endpoint is mounted at /_anycable" do
    # The AnyCable HTTP RPC endpoint should be mounted and respond
    # Even without proper AnyCable headers, it should not 404
    post "/_anycable/connect", as: :json

    # AnyCable RPC returns 422 for malformed requests (missing required fields)
    # but NOT 404, which would indicate the endpoint isn't mounted
    assert_not_equal 404, response.status, "AnyCable RPC endpoint not mounted at /_anycable"
  end

  test "AnyCable configuration is loaded" do
    assert AnyCable.config.http_rpc_mount_path.present?, "HTTP RPC mount path not configured"
    assert_equal "/_anycable", AnyCable.config.http_rpc_mount_path
    assert_equal "http", AnyCable.config.broadcast_adapter.to_s
  end
end
