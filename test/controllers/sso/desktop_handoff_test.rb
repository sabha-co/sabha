require "test_helper"

class Sso::DesktopHandoffTest < ActionDispatch::IntegrationTest
  CODE_CHALLENGE = Desktop::SessionClaim.code_challenge_for("desktop-code-verifier")

  setup do
    host! "once.sabha.test"
    ENV["AUTH_METHOD"] = "sso"
    ENV["SSO_PROVIDER_URL"] = "https://sso.example.com/session/sso"
    ENV["SSO_SECRET"] = "test-sso-secret"
  end

  teardown do
    ENV.delete("AUTH_METHOD")
    ENV.delete("SSO_PROVIDER_URL")
    ENV.delete("SSO_SECRET")
  end

  test "successful sso callback with desktop handoff redirects to a one-time claim deep link" do
    get sso_handshake_url, params: handoff_params(return_to: "/chat")
    assert_response :success

    assert_difference -> { Desktop::SessionClaim.count }, 1 do
      complete_sso_as users(:david)
    end

    assert_redirected_to %r{\Asabha://session-claim\?}
    claim = Desktop::SessionClaim.last
    assert_equal "handoff-nonce", claim.nonce
    assert_equal "https://once.sabha.test", claim.origin
    assert_equal CODE_CHALLENGE, claim.code_challenge
    assert_equal "/chat", claim.return_path
  end

  test "desktop handoff falls back to root for an off-site return path" do
    get sso_handshake_url, params: handoff_params(return_to: "//evil.example/steal")
    complete_sso_as users(:david)

    assert_equal "/", Desktop::SessionClaim.last.return_path
  end

  test "desktop handoff without a code challenge is ignored" do
    get sso_handshake_url, params: handoff_params.except(:desktop_code_challenge)

    assert_no_difference -> { Desktop::SessionClaim.count } do
      complete_sso_as users(:david)
    end
    assert_redirected_to root_url
  end

  test "an abandoned desktop handoff does not hijack a later browser sign-in" do
    get sso_handshake_url, params: handoff_params
    get sso_handshake_url

    assert_no_difference -> { Desktop::SessionClaim.count } do
      complete_sso_as users(:david)
    end
    assert_redirected_to root_url
  end

  test "browser sso without desktop handoff still sets a session cookie" do
    get sso_handshake_url
    assert_response :success

    complete_sso_as users(:david)

    assert_redirected_to root_url
    assert parsed_cookies.signed[:session_token]
    assert_empty Desktop::SessionClaim.valid
  end

  private
    def handoff_params(**overrides)
      {
        desktop_handoff: "1",
        desktop_nonce: "handoff-nonce",
        desktop_origin: "https://once.sabha.test",
        desktop_code_challenge: CODE_CHALLENGE
      }.merge(overrides)
    end

    def complete_sso_as(user)
      payload = {
        nonce: session["single_sign_on_nonce"],
        external_id: single_sign_on_records(:david).external_id,
        email: user.email_address,
        name: user.name
      }
      sso, sig = Sso::Payload.encode(payload, ENV["SSO_SECRET"])
      get sso_callback_url, params: { sso: sso, sig: sig }
    end
end
