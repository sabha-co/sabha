require "test_helper"

# Connecting "Continue with sabha.co" to an account that already exists here
class Users::HubLinksControllerTest < ActionDispatch::IntegrationTest
  HUB_SECRET = "hub-secret"

  setup do
    @original_env = ENV.to_h.slice("AUTH_METHOD", "SABHA_HUB_SECRET")
    ENV["AUTH_METHOD"] = "password"
    ENV["SABHA_HUB_SECRET"] = HUB_SECRET
  end

  teardown do
    %w[ AUTH_METHOD SABHA_HUB_SECRET ].each do |key|
      @original_env.key?(key) ? ENV[key] = @original_env[key] : ENV.delete(key)
    end
  end

  test "the sign-in page offers sabha.co beside the workspace's own login" do
    get new_session_url

    assert_select "a[href=?]", hub_handshake_path, text: /Continue with sabha.co/
  end

  test "the sign-in page doesn't offer sabha.co to a workspace that isn't connected" do
    ENV.delete("SABHA_HUB_SECRET")

    get new_session_url

    assert_select "a[href^='/session/hub']", count: 0
  end

  test "the invite page carries the invite through sabha.co" do
    join_code = Current.account.join_code

    get join_url(join_code.code)

    assert_select "a[href=?]", hub_handshake_path(join_code: join_code.code), text: /Continue with sabha.co/
  end

  test "the profile offers to connect sabha.co" do
    sign_in :david

    get user_profile_url

    assert_select "a.setting-row[href=?]", new_user_hub_link_path, text: /Connect sabha.co/
  end

  test "the profile shows the connected sabha.co account and hides the list prompt" do
    link_hub(users(:david), "global_identity:1", email: "david@sabha.co")
    sign_in :david

    get user_profile_url
    assert_select ".setting-row", text: /Connected as david@sabha.co/
    assert_select "a[href^='https://sabha.co/remote_workspaces']", count: 0

    get user_sidebar_url
    assert_select "#hub_list_prompt", count: 0
  end

  test "connecting right after signing in goes straight to sabha.co" do
    sign_in :david

    get new_user_hub_link_url
    assert_select "button", text: "Continue to sabha.co"

    post user_hub_link_url
    assert_redirected_to hub_handshake_url
  end

  test "connecting later asks the member to confirm it's them" do
    sign_in :david

    travel 11.minutes do
      get new_user_hub_link_url
      assert_select "h1", text: "Confirm it's you"

      post user_hub_link_url
      assert_redirected_to new_user_hub_link_url
    end
  end

  test "signing in again comes back to connect sabha.co" do
    sign_in :david

    delete session_url, params: { return_to: new_user_hub_link_path }

    assert_redirected_to new_session_url(return_to: new_user_hub_link_path)
  end

  test "connects the sabha.co account the member picks, whatever its email" do
    sign_in :david
    post user_hub_link_url
    get hub_handshake_url

    complete_hub_sign_in(external_id: "global_identity:1", email: "someone-else@example.com")

    assert_redirected_to user_profile_url
    assert_equal "global_identity:1", users(:david).hub_link.external_id
  end

  test "a sabha.co account that signs in to someone else can't be connected" do
    link_hub(users(:jason), "global_identity:1")
    sign_in :david
    post user_hub_link_url
    get hub_handshake_url

    complete_hub_sign_in(external_id: "global_identity:1", email: "someone@example.com")

    assert_response :forbidden
    assert_match "already connected to a different account", response.body
    assert_not users(:david).hub_linked?
  end

  test "an unverified sabha.co email is never connected" do
    sign_in :david
    post user_hub_link_url
    get hub_handshake_url

    complete_hub_sign_in(external_id: "global_identity:1", email: "someone@example.com", require_activation: "true")

    assert_not users(:david).hub_linked?
  end

  test "a connect request that went stale is treated as an ordinary sign-in" do
    sign_in :david
    post user_hub_link_url
    get hub_handshake_url

    travel 11.minutes do
      complete_hub_sign_in(external_id: "global_identity:1", email: users(:david).email_address)
    end

    assert_response :forbidden
    assert_not users(:david).hub_linked?
  end

  test "disconnects sabha.co" do
    link_hub(users(:david), "global_identity:1")
    sign_in :david

    delete user_hub_link_url

    assert_redirected_to user_profile_url
    assert_not users(:david).hub_linked?
  end

  test "won't disconnect a member's only way to sign in" do
    link_hub(users(:david), "global_identity:1")
    sign_in :david
    users(:david).update_column(:password_digest, nil)

    delete user_hub_link_url

    assert_redirected_to user_profile_url
    assert_match "Set a password", flash[:alert]
    assert users(:david).hub_linked?
  end

  test "email-code workspaces can always disconnect" do
    link_hub(users(:david), "global_identity:1")
    sign_in :david
    ENV["AUTH_METHOD"] = "otp"
    users(:david).update_column(:password_digest, nil)

    delete user_hub_link_url

    assert_not users(:david).hub_linked?
  end

  test "isn't there when the workspace isn't connected to sabha.co" do
    sign_in :david
    ENV.delete("SABHA_HUB_SECRET")

    get new_user_hub_link_url

    assert_response :not_found
  end

  private
    def link_hub(user, external_id, email: nil)
      user.single_sign_on_records.create!(issuer: "https://sabha.co", external_id:, external_email: email)
    end

    def complete_hub_sign_in(**attributes)
      payload = { nonce: session["hub_sign_on_nonce"], name: "Member" }.merge(attributes)
      sso, sig = Sso::Payload.encode(payload, HUB_SECRET)
      get hub_callback_url, params: { sso:, sig: }
    end
end
