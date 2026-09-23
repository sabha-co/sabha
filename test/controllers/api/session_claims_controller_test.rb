require "test_helper"

class API::SessionClaimsControllerTest < ActionDispatch::IntegrationTest
  VERIFIER = "desktop-code-verifier-0123456789-abcdefghijklmnop"

  setup { host! "once.sabha.test" }

  test "redeems a valid claim once and establishes a session" do
    claim = issue_claim(nonce: "nonce-abc", return_path: "/chat")

    post "/api/session_claim",
      params: { token: claim.raw_token, nonce: "nonce-abc", origin: "https://once.sabha.test", code_verifier: VERIFIER },
      headers: desktop_headers

    assert_response :success
    assert_equal "/chat", JSON.parse(response.body)["return_path"]
    assert parsed_cookies.signed[:session_token]
    assert claim.reload.used_at
  end

  test "rejects a replayed claim" do
    claim = issue_claim(nonce: "nonce-replay")
    params = { token: claim.raw_token, nonce: "nonce-replay", origin: "https://once.sabha.test", code_verifier: VERIFIER }

    post "/api/session_claim", params: params, headers: desktop_headers
    assert_response :success

    post "/api/session_claim", params: params, headers: desktop_headers
    assert_response :forbidden
  end

  test "rejects an intercepted deep link redeemed without the verifier" do
    claim = issue_claim(nonce: "nonce-intercepted")
    params = { token: claim.raw_token, nonce: "nonce-intercepted", origin: "https://once.sabha.test" }

    post "/api/session_claim", params: params, headers: desktop_headers
    assert_response :forbidden

    post "/api/session_claim", params: params.merge(code_verifier: "guessed-verifier"), headers: desktop_headers
    assert_response :forbidden

    assert_nil parsed_cookies.signed[:session_token]
    assert_nil claim.reload.used_at
  end

  test "does not persist the raw bearer token" do
    claim = issue_claim(nonce: "nonce-digest")

    assert claim.raw_token.present?
    assert_equal Session::Claim.digest(claim.raw_token), claim.token_digest
    refute Session::Claim.column_names.include?("token")
  end

  private
    def issue_claim(nonce:, return_path: "/")
      Session::Claim.issue!(
        user: users(:david),
        nonce: nonce,
        origin: "https://once.sabha.test",
        code_challenge: Session::Claim.code_challenge_for(VERIFIER),
        return_path: return_path
      )
    end

    def desktop_headers
      { "Sabha-Protocol-Major" => "1" }
    end
end
