require "test_helper"

class Sso::DesktopHandoffTest < ActionDispatch::IntegrationTest
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
    get sso_handshake_url,
      params: {
        desktop_handoff: "1",
        desktop_nonce: "handoff-nonce",
        desktop_origin: "https://once.sabha.test",
        return_to: "/chat"
      }
    assert_response :success

    nonce = session["single_sign_on_nonce"]
    payload = {
      nonce: nonce,
      external_id: single_sign_on_records(:david).external_id,
      email: users(:david).email_address,
      name: users(:david).name
    }
    sso, sig = Sso::Payload.encode(payload, ENV["SSO_SECRET"])

    assert_difference -> { Desktop::SessionClaim.count }, 1 do
      get sso_callback_url, params: { sso: sso, sig: sig }
    end

    assert_redirected_to %r{\Asabha://session-claim\?}
    claim = Desktop::SessionClaim.last
    assert_equal "handoff-nonce", claim.nonce
    assert_equal "https://once.sabha.test", claim.origin
    assert_equal "/chat", claim.return_path
  end

  test "browser sso without desktop handoff still sets a session cookie" do
    get sso_handshake_url
    assert_response :success

    nonce = session["single_sign_on_nonce"]
    payload = {
      nonce: nonce,
      external_id: single_sign_on_records(:david).external_id,
      email: users(:david).email_address,
      name: users(:david).name
    }
    sso, sig = Sso::Payload.encode(payload, ENV["SSO_SECRET"])

    get sso_callback_url, params: { sso: sso, sig: sig }

    assert_redirected_to root_url
    assert parsed_cookies.signed[:session_token]
    assert_empty Desktop::SessionClaim.valid
  end
end
