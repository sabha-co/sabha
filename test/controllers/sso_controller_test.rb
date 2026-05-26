require "test_helper"

class SsoFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @original_auth_method = ENV["AUTH_METHOD"]
    @original_provider_url = ENV["SSO_PROVIDER_URL"]
    @original_secret = ENV["SSO_SECRET"]

    ENV["AUTH_METHOD"] = "sso"
    ENV["SSO_PROVIDER_URL"] = "https://parent.example.com/sso"
    ENV["SSO_SECRET"] = "test-sso-secret"
  end

  teardown do
    restore_env("AUTH_METHOD", @original_auth_method)
    restore_env("SSO_PROVIDER_URL", @original_provider_url)
    restore_env("SSO_SECRET", @original_secret)
  end

  test "new redirects to provider with signed payload" do
    get sso_handshake_url, params: { return_to: "/rooms/general" }

    assert_response :redirect
    assert_match %r{\Ahttps://parent\.example\.com/sso\?}, response.location

    payload = provider_request_payload
    assert payload["nonce"].present?
    assert_equal sso_callback_url, payload["return_sso_url"]
  end

  test "new rejects unsafe return path" do
    get sso_handshake_url, params: { return_to: "https://evil.example.com/hijack" }
    nonce = provider_request_payload["nonce"]

    sso, sig = Sso::Payload.encode(callback_payload(nonce:), ENV["SSO_SECRET"])
    get sso_callback_url, params: { sso:, sig: }

    assert_redirected_to root_url
  end

  test "valid callback signs in existing sso user" do
    get sso_handshake_url, params: { return_to: "/chat" }
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: users(:david).email_address, external_id: single_sign_on_records(:david).external_id), ENV["SSO_SECRET"])

    assert_difference -> { Session.count }, +1 do
      get sso_callback_url, params: { sso:, sig: }
    end

    assert_redirected_to "/chat"
    assert parsed_cookies.signed[:session_token].present?
  end

  test "valid callback creates verified user" do
    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: "new-sso@example.com", external_id: "new-sso-user"), ENV["SSO_SECRET"])

    assert_difference -> { User.count }, +1 do
      assert_difference -> { SingleSignOnRecord.count }, +1 do
        get sso_callback_url, params: { sso:, sig: }
      end
    end

    assert_response :redirect
    assert parsed_cookies.signed[:session_token].present?
    assert User.find_by(email_address: "new-sso@example.com").verified?
  end

  test "bad signature is forbidden and does not consume nonce" do
    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:), ENV["SSO_SECRET"])

    get sso_callback_url, params: { sso:, sig: "bad-signature" }
    assert_response :forbidden

    get sso_callback_url, params: { sso:, sig: }
    assert_response :redirect
    assert parsed_cookies.signed[:session_token].present?
  end

  test "callback rejects nonce not bound to current browser session" do
    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:), ENV["SSO_SECRET"])

    reset!  # simulate a different browser (fresh cookies/session)

    get sso_callback_url, params: { sso:, sig: }

    assert_response :forbidden
    assert_not SingleSignOnNonce.find_by(nonce:).used?
  end

  test "replayed nonce is forbidden" do
    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:), ENV["SSO_SECRET"])

    get sso_callback_url, params: { sso:, sig: }
    assert_response :redirect

    get sso_callback_url, params: { sso:, sig: }
    assert_response :forbidden
  end

  test "expired nonce is forbidden" do
    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:), ENV["SSO_SECRET"])

    travel 31.minutes do
      get sso_callback_url, params: { sso:, sig: }
    end

    assert_response :forbidden
  end

  test "failed payload renders failure without session" do
    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode({ nonce:, failed: "true" }, ENV["SSO_SECRET"])

    assert_no_difference -> { Session.count } do
      get sso_callback_url, params: { sso:, sig: }
    end

    assert_response :unauthorized
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "callback rate limits repeated attempts" do
    10.times do
      get sso_callback_url
      assert_response :forbidden
    end

    get sso_callback_url

    assert_response :too_many_requests
  end

  test "signed logout payload terminates current session" do
    ENV["AUTH_METHOD"] = "password"
    sign_in :david
    session_id = users(:david).sessions.last.id
    ENV["AUTH_METHOD"] = "sso"

    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode({ nonce:, logout: "true" }, ENV["SSO_SECRET"])

    get sso_callback_url, params: { sso:, sig: }

    assert_response :redirect
    assert_not Session.exists?(session_id)
    assert_nil parsed_cookies.signed[:session_token]
  end

  test "logout payload with invalid signature does not terminate current session" do
    ENV["AUTH_METHOD"] = "password"
    sign_in :david
    session_id = users(:david).sessions.last.id
    ENV["AUTH_METHOD"] = "sso"

    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, = Sso::Payload.encode({ nonce:, logout: "true" }, ENV["SSO_SECRET"])

    get sso_callback_url, params: { sso:, sig: "bad-signature" }

    assert_response :forbidden
    assert Session.exists?(session_id)
  end

  test "require activation sends verification email without session" do
    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: "verify-sso@example.com", external_id: "verify-sso", require_activation: "true"), ENV["SSO_SECRET"])

    assert_enqueued_emails 1 do
      get sso_callback_url, params: { sso:, sig: }
    end

    assert_response :unauthorized
    assert_nil parsed_cookies.signed[:session_token]
    assert_not User.find_by(email_address: "verify-sso@example.com").verified?
  end

  test "join code is redeemed after successful sso signup" do
    join_code = Current.account.join_code
    code = join_code.code

    get join_url(code)
    assert_redirected_to sso_handshake_url(return_to: "/join/#{code}")
    assert_equal code, session[:pending_join_code]

    get sso_handshake_url, params: { return_to: "/join/#{code}" }
    nonce = provider_request_payload["nonce"]

    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: "joiner@example.com", external_id: "joiner-1"), ENV["SSO_SECRET"])

    assert_difference -> { join_code.reload.usage_count }, +1 do
      get sso_callback_url, params: { sso:, sig: }
    end

    assert_redirected_to "/join/#{code}"
    assert_nil session[:pending_join_code]
  end

  test "inactive join code aborts new user signup and refuses sign-in" do
    join_code = Current.account.join_code
    code = join_code.code

    get join_url(code)
    get sso_handshake_url, params: { return_to: "/join/#{code}" }
    nonce = provider_request_payload["nonce"]

    join_code.update!(expires_at: 1.day.ago)

    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: "late-joiner@example.com", external_id: "late-joiner"), ENV["SSO_SECRET"])

    assert_no_difference -> { join_code.reload.usage_count } do
      assert_no_difference -> { User.count } do
        get sso_callback_url, params: { sso:, sig: }
      end
    end

    assert_response :unauthorized
    assert_nil parsed_cookies.signed[:session_token]
    assert_nil User.find_by(email_address: "late-joiner@example.com")
  end

  test "inactive join code is ignored when an existing sso user signs in" do
    join_code = Current.account.join_code
    code = join_code.code

    get join_url(code)
    get sso_handshake_url, params: { return_to: "/join/#{code}" }
    nonce = provider_request_payload["nonce"]

    join_code.update!(expires_at: 1.day.ago)

    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: users(:david).email_address, external_id: single_sign_on_records(:david).external_id), ENV["SSO_SECRET"])

    assert_no_difference -> { join_code.reload.usage_count } do
      get sso_callback_url, params: { sso:, sig: }
    end

    assert_redirected_to "/join/#{code}"
    assert parsed_cookies.signed[:session_token].present?
  end

  test "first sso callback bootstraps account and provisions an administrator" do
    ActiveRecord::Base.connection.disable_referential_integrity do
      Account.destroy_all
      Room.destroy_all
      User.destroy_all
    end

    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: "founder@example.com", external_id: "founder-1", name: "Founder"), ENV["SSO_SECRET"])

    assert_difference -> { Account.count }, +1 do
      assert_difference -> { User.count }, +1 do
        get sso_callback_url, params: { sso:, sig: }
      end
    end

    admin = User.find_by(email_address: "founder@example.com")
    assert admin.administrator?
    assert_includes admin.rooms.map(&:name), "General"
    assert_match /Welcome to/, flash[:notice]
  end

  test "newly provisioned sso user sees a welcome flash" do
    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: "newcomer@example.com", external_id: "newcomer-1", name: "Newcomer"), ENV["SSO_SECRET"])

    get sso_callback_url, params: { sso:, sig: }

    assert_match /Welcome to/, flash[:notice]
  end

  test "returning sso user does not see the welcome flash" do
    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: users(:david).email_address, external_id: single_sign_on_records(:david).external_id), ENV["SSO_SECRET"])

    get sso_callback_url, params: { sso:, sig: }

    assert_nil flash[:notice]
  end

  test "misconfiguration fails closed" do
    ENV.delete("SSO_SECRET")

    get sso_handshake_url

    assert_response :service_unavailable
  end

  test "configured sso endpoint fails closed when sso auth is disabled and not bootstrapping" do
    ENV["AUTH_METHOD"] = "password"

    get sso_handshake_url

    assert_response :service_unavailable
  end

  test "sso callback accepts bootstrap traffic and provisions admin when auth_method != sso" do
    ENV["AUTH_METHOD"] = "password"
    ENV["AUTO_BOOTSTRAP"] = "true"

    ActiveRecord::Base.connection.disable_referential_integrity do
      Account.destroy_all
      Room.destroy_all
      User.destroy_all
    end

    get sso_handshake_url
    nonce = provider_request_payload["nonce"]
    sso, sig = Sso::Payload.encode(callback_payload(nonce:, email: "boot@example.com", external_id: "boot-1", name: "Boot"), ENV["SSO_SECRET"])

    assert_difference -> { Account.count }, +1 do
      assert_difference -> { User.count }, +1 do
        get sso_callback_url, params: { sso:, sig: }
      end
    end

    assert User.find_by(email_address: "boot@example.com").administrator?
  ensure
    ENV.delete("AUTO_BOOTSTRAP")
  end

  private
    def provider_request_payload
      uri = URI.parse(response.location)
      query = Rack::Utils.parse_query(uri.query)
      Sso::Payload.decode(query["sso"], query["sig"], ENV["SSO_SECRET"])
    end

    def callback_payload(attributes = {})
      {
        nonce: "nonce",
        email: "sso-person@example.com",
        external_id: "sso-person",
        name: "SSO Person",
        require_activation: "false"
      }.merge(attributes)
    end

    def restore_env(key, value)
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
end
