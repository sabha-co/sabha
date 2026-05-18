require "test_helper"

class Sso::UserResolverTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @original_overrides_name = ENV["SSO_OVERRIDES_NAME"]
    @original_overrides_avatar = ENV["SSO_OVERRIDES_AVATAR"]
    ENV.delete("SSO_OVERRIDES_NAME")
    ENV.delete("SSO_OVERRIDES_AVATAR")
  end

  teardown do
    restore_env("SSO_OVERRIDES_NAME", @original_overrides_name)
    restore_env("SSO_OVERRIDES_AVATAR", @original_overrides_avatar)
  end

  test "creates verified user and sso record for new verified email" do
    assert_difference -> { User.count }, +1 do
      assert_difference -> { SingleSignOnRecord.count }, +1 do
        result = Sso::UserResolver.resolve(payload(email: "new@example.com", external_id: "new-1", name: "New User"))

        assert result.session_allowed?
        assert_not result.activation_required?
        assert result.user.verified?
        assert_equal "New User", result.user.name
        assert_equal "new@example.com", result.user.email_address
        assert_equal "new-1", result.user.single_sign_on_record.external_id
        assert_equal "new@example.com", result.user.single_sign_on_record.external_email
      end
    end
  end

  test "updates audit fields for existing external id" do
    record = single_sign_on_records(:david)

    result = Sso::UserResolver.resolve(payload(email: "david.changed@example.com", external_id: record.external_id))

    assert result.session_allowed?
    assert_equal users(:david), result.user
    assert_equal "david.changed@example.com", record.reload.external_email
    assert record.last_payload.include?("david.changed@example.com")
    assert_in_delta Time.current, record.last_seen_at, 2.seconds
  end

  test "claims existing email without sso record when activation is not required" do
    user = users(:jason)

    assert_difference -> { User.count }, 0 do
      assert_difference -> { SingleSignOnRecord.count }, +1 do
        result = Sso::UserResolver.resolve(payload(email: user.email_address, external_id: "jason-provider"))

        assert result.session_allowed?
        assert_equal user, result.user
        assert_equal "jason-provider", user.single_sign_on_record.external_id
      end
    end
  end

  test "preserves local profile fields without override flags" do
    user = users(:david)

    Sso::UserResolver.resolve(payload(
      email: user.email_address,
      external_id: single_sign_on_records(:david).external_id,
      name: "Provider Name",
      avatar_url: "https://example.com/provider.png"
    ))

    assert_equal "David", user.reload.name
    assert_nil user.avatar_url
  end

  test "updates local profile fields with override flags" do
    ENV["SSO_OVERRIDES_NAME"] = "true"
    ENV["SSO_OVERRIDES_AVATAR"] = "true"
    user = users(:david)

    Sso::UserResolver.resolve(payload(
      email: user.email_address,
      external_id: single_sign_on_records(:david).external_id,
      name: "Provider Name",
      avatar_url: "https://example.com/provider.png"
    ))

    assert_equal "Provider Name", user.reload.name
    assert_equal "https://example.com/provider.png", user.avatar_url
  end

  test "rejects email claimed by another external id" do
    result = Sso::UserResolver.resolve(payload(email: users(:david).email_address, external_id: "attacker"))

    assert result.failure?
    assert_not result.session_allowed?
    assert_nil result.user
  end

  test "require activation does not claim existing email" do
    user = users(:jason)

    assert_no_difference -> { SingleSignOnRecord.count } do
      result = Sso::UserResolver.resolve(payload(email: user.email_address, external_id: "jason-provider", require_activation: true))

      assert result.failure?
      assert_not result.session_allowed?
    end
  end

  test "require activation creates unverified user and sends verification email" do
    assert_enqueued_emails 1 do
      result = Sso::UserResolver.resolve(payload(email: "activate@example.com", external_id: "activate-1", require_activation: true))

      assert_not result.failure?
      assert_not result.session_allowed?
      assert result.activation_required?
      assert_not result.user.verified?
      assert_equal "activate-1", result.user.single_sign_on_record.external_id
    end
  end

  test "require activation for linked unverified user sends verification email without session" do
    user = users(:david)
    user.update!(verified_at: nil)

    assert_enqueued_emails 1 do
      result = Sso::UserResolver.resolve(payload(email: user.email_address, external_id: single_sign_on_records(:david).external_id, require_activation: true))

      assert_not result.failure?
      assert_not result.session_allowed?
      assert result.activation_required?
      assert_equal user, result.user
    end
  end

  private
    def payload(attributes = {})
      {
        "email" => "person@example.com",
        "external_id" => "person-1",
        "name" => "Person",
        "avatar_url" => nil,
        "require_activation" => false
      }.merge(attributes.stringify_keys)
    end

    def restore_env(key, value)
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
end
