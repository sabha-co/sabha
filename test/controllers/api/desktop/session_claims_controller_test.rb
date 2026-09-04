require "test_helper"

class API::Desktop::SessionClaimsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "once.sabha.test" }

  test "redeems a valid claim once and establishes a session" do
    user = users(:david)
    claim = Desktop::SessionClaim.issue!(
      user: user,
      nonce: "nonce-abc",
      origin: "https://once.sabha.test",
      return_path: "/chat"
    )

    post "/api/desktop/session_claim",
      params: { token: claim.raw_token, nonce: "nonce-abc", origin: "https://once.sabha.test" },
      headers: desktop_headers

    assert_response :success
    assert_equal "/chat", JSON.parse(response.body)["return_path"]
    assert parsed_cookies.signed[:session_token]
    assert claim.reload.used?
  end

  test "rejects a replayed claim" do
    user = users(:david)
    claim = Desktop::SessionClaim.issue!(
      user: user,
      nonce: "nonce-replay",
      origin: "https://once.sabha.test",
      return_path: "/"
    )
    params = { token: claim.raw_token, nonce: "nonce-replay", origin: "https://once.sabha.test" }

    post "/api/desktop/session_claim", params: params, headers: desktop_headers
    assert_response :success

    post "/api/desktop/session_claim", params: params, headers: desktop_headers
    assert_response :forbidden
  end

  test "does not persist the raw bearer token" do
    user = users(:david)
    claim = Desktop::SessionClaim.issue!(
      user: user,
      nonce: "nonce-digest",
      origin: "https://once.sabha.test",
      return_path: "/"
    )

    assert claim.raw_token.present?
    assert_equal Desktop::SessionClaim.digest(claim.raw_token), claim.token_digest
    refute Desktop::SessionClaim.column_names.include?("token")
  end

  private
    def desktop_headers
      { "Sabha-Desktop-Protocol-Major" => "1", "Sabha-Desktop-Client" => "1" }
    end
end
