require "test_helper"

# "Continue with sabha.co": one more way into a self-hosted workspace, beside
# its own password or email codes.
class Sso::HubSignInTest < ActionDispatch::IntegrationTest
  HUB_SECRET = "hub-secret"
  CODE_CHALLENGE = Session::Claim.code_challenge_for("app-code-verifier")

  setup do
    @original_env = ENV.to_h.slice("AUTH_METHOD", "SABHA_HUB_SECRET", "SSO_PROVIDER_URL", "SSO_SECRET")
    ENV["AUTH_METHOD"] = "password"
    ENV["SABHA_HUB_SECRET"] = HUB_SECRET
  end

  teardown do
    %w[ AUTH_METHOD SABHA_HUB_SECRET SSO_PROVIDER_URL SSO_SECRET ].each do |key|
      @original_env.key?(key) ? ENV[key] = @original_env[key] : ENV.delete(key)
    end
  end

  test "sends the member to sabha.co with a signed request that returns to the hub callback" do
    get hub_handshake_url

    assert_response :ok
    assert_equal "https://sabha.co/session/sso", provider_form["action"]
    assert_equal hub_callback_url, provider_request_payload["return_sso_url"]
  end

  test "signs in a member who connected sabha.co" do
    link_hub(users(:david), "global_identity:1")

    get hub_handshake_url
    assert_difference -> { Session.count }, +1 do
      complete_hub_sign_in(external_id: "global_identity:1", email: users(:david).email_address)
    end

    assert_redirected_to root_url
    assert parsed_cookies.signed[:session_token].present?
  end

  test "never matches an unconnected account by email" do
    get hub_handshake_url
    assert_no_difference -> { Session.count } do
      complete_hub_sign_in(external_id: "global_identity:9", email: users(:david).email_address)
    end

    assert_response :forbidden
    assert_match "connect sabha.co from your profile", response.body
    assert_empty users(:david).single_sign_on_records.where(issuer: "https://sabha.co")
  end

  test "someone new needs an invite" do
    get hub_handshake_url
    assert_no_difference -> { User.count } do
      complete_hub_sign_in(external_id: "global_identity:9", email: "newcomer@example.com")
    end

    assert_response :forbidden
    assert_match "You need an invite", response.body
  end

  test "someone new with an invite joins and is linked" do
    get hub_handshake_url, params: { join_code: Current.account.join_code.code }
    assert_difference -> { User.count }, +1 do
      complete_hub_sign_in(external_id: "global_identity:9", email: "newcomer@example.com", name: "Newcomer")
    end

    user = User.find_by!(email_address: "newcomer@example.com")
    assert_equal [ [ "https://sabha.co", "global_identity:9" ] ], user.single_sign_on_records.pluck(:issuer, :external_id)
    assert user.verified?
    assert_redirected_to root_url
  end

  test "a made-up invite doesn't let someone new in" do
    get hub_handshake_url, params: { join_code: "not-a-code" }

    assert_no_difference -> { User.count } do
      complete_hub_sign_in(external_id: "global_identity:9", email: "newcomer@example.com")
    end
    assert_response :forbidden
  end

  test "an unverified sabha.co email never creates or links an account" do
    get hub_handshake_url, params: { join_code: Current.account.join_code.code }
    assert_no_difference -> { User.count } do
      complete_hub_sign_in(external_id: "global_identity:9", email: "newcomer@example.com", require_activation: true)
    end
    assert_match "verify your email", response.body
  end

  test "sabha.co doesn't overwrite the member's profile" do
    link_hub(users(:david), "global_identity:1")
    ENV["SSO_OVERRIDES_NAME"] = "true"

    get hub_handshake_url
    complete_hub_sign_in(external_id: "global_identity:1", email: users(:david).email_address, name: "Someone Else")

    assert_not_equal "Someone Else", users(:david).reload.name
  ensure
    ENV.delete("SSO_OVERRIDES_NAME")
  end

  test "a payload signed with another secret is refused" do
    get hub_handshake_url
    sso, sig = Sso::Payload.encode({ nonce: session["hub_sign_on_nonce"], external_id: "x", email: "x@example.com" }, "someone-elses-secret")

    get hub_callback_url, params: { sso:, sig: }

    assert_response :forbidden
  end

  test "a signed payload whose nonce this browser wasn't given is refused" do
    link_hub(users(:david), "global_identity:1")

    get hub_handshake_url
    sso, sig = Sso::Payload.encode({ nonce: "made-up", external_id: "global_identity:1", email: users(:david).email_address }, HUB_SECRET)

    assert_no_difference -> { Session.count } do
      get hub_callback_url, params: { sso:, sig: }
    end
    assert_response :forbidden
  end

  test "hands a sign-in back to a Sabha app with a session claim" do
    link_hub(users(:david), "global_identity:1")

    get hub_handshake_url, params: { handoff: "1", handoff_nonce: "n", handoff_origin: "https://once.sabha.test", code_challenge: CODE_CHALLENGE }
    complete_hub_sign_in(external_id: "global_identity:1", email: users(:david).email_address)

    assert_match %r{\Asabha://session-claim\?}, response.location
    assert_equal users(:david), Session::Claim.redeemable.sole.user
  end

  test "isn't offered beside the workspace's own single sign-on" do
    ENV["AUTH_METHOD"] = "sso"
    ENV["SSO_PROVIDER_URL"] = "https://sso.example/sso"
    ENV["SSO_SECRET"] = "custom-secret"

    get hub_handshake_url

    assert_response :not_found
  end

  test "isn't offered without a sabha.co secret" do
    ENV.delete("SABHA_HUB_SECRET")

    get hub_handshake_url

    assert_response :not_found
  end

  private
    def link_hub(user, external_id)
      user.single_sign_on_records.create!(issuer: "https://sabha.co", external_id:)
    end

    def complete_hub_sign_in(**attributes)
      payload = { nonce: session["hub_sign_on_nonce"], name: "Member" }.merge(attributes)
      payload[:require_activation] = payload[:require_activation].to_s if payload.key?(:require_activation)
      sso, sig = Sso::Payload.encode(payload, HUB_SECRET)
      get hub_callback_url, params: { sso:, sig: }
    end

    def provider_form
      css_select("form[data-controller~='auto-submit']").first
    end

    def provider_request_payload
      form = provider_form
      Sso::Payload.decode(form.at_css("input[name='sso']")["value"], form.at_css("input[name='sig']")["value"], HUB_SECRET)
    end
end
