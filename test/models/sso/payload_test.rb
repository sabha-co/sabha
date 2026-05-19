require "test_helper"

class Sso::PayloadTest < ActiveSupport::TestCase
  SECRET = "super-secret-sso-key"

  test "round trips encoded payload" do
    sso, sig = Sso::Payload.encode({ nonce: "abc123", return_sso_url: "https://chat.example.com/session/sso/callback" }, SECRET)

    payload = Sso::Payload.decode(sso, sig, SECRET)

    assert_equal "abc123", payload["nonce"]
    assert_equal "https://chat.example.com/session/sso/callback", payload["return_sso_url"]
  end

  test "decodes supported response fields" do
    sso, sig = Sso::Payload.encode({
      nonce: "abc123",
      email: "david@example.com",
      external_id: "user-1",
      name: "David",
      avatar_url: "https://example.com/avatar.png",
      require_activation: "false"
    }, SECRET)

    payload = Sso::Payload.decode(sso, sig, SECRET)

    assert_equal "david@example.com", payload["email"]
    assert_equal "user-1", payload["external_id"]
    assert_equal "David", payload["name"]
    assert_equal "https://example.com/avatar.png", payload["avatar_url"]
    assert_equal false, payload["require_activation"]
  end

  test "decodes booleans with discourse semantics" do
    sso, sig = Sso::Payload.encode({
      nonce: "abc123",
      external_id: "user-1",
      require_activation: "true",
      logout: "false",
      admin: "garbage"
    }, SECRET)

    payload = Sso::Payload.decode(sso, sig, SECRET)

    assert_equal true, payload["require_activation"]
    assert_equal false, payload["logout"]
    assert_not payload.key?("admin")
  end

  test "decodes custom fields" do
    sso, sig = Sso::Payload.encode({
      nonce: "abc123",
      external_id: "user-1",
      "custom.plan" => "pro"
    }, SECRET)

    payload = Sso::Payload.decode(sso, sig, SECRET)

    assert_equal({ "plan" => "pro" }, payload["custom_fields"])
  end

  test "raises on signature mismatch" do
    sso, = Sso::Payload.encode({ nonce: "abc123", external_id: "user-1" }, SECRET)

    assert_raises Sso::Payload::InvalidSignature do
      Sso::Payload.decode(sso, "bad-signature", SECRET)
    end
  end

  test "rejects non base64 characters before decode" do
    assert_raises Sso::Payload::InvalidPayload do
      Sso::Payload.decode("not valid?!", "ignored", SECRET)
    end
  end

  test "raises on malformed payload" do
    sso = Base64.strict_encode64("%")
    sig = Sso::Payload.sign(sso, SECRET)

    assert_raises Sso::Payload::InvalidPayload do
      Sso::Payload.decode(sso, sig, SECRET)
    end
  end

  test "downcases external_id so case-variant providers don't fork records" do
    sso, sig = Sso::Payload.encode({ nonce: "abc123", external_id: "User-One" }, SECRET)

    payload = Sso::Payload.decode(sso, sig, SECRET)

    assert_equal "user-one", payload["external_id"]
  end

  test "rejects banned external ids" do
    sso, sig = Sso::Payload.encode({ nonce: "abc123", external_id: "null" }, SECRET)

    assert_raises Sso::Payload::BannedExternalId do
      Sso::Payload.decode(sso, sig, SECRET)
    end
  end
end
