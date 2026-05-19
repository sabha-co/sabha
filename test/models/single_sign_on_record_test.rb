require "test_helper"

class SingleSignOnRecordTest < ActiveSupport::TestCase
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

  test "belongs to user and stores provider audit fields" do
    record = single_sign_on_records(:david)

    assert_equal users(:david), record.user
    assert_equal "provider-david", record.external_id
    assert_equal "david@37signals.com", record.external_email
    assert_equal "nonce=abc&external_id=provider-david&email=david@37signals.com", record.last_payload
    assert record.last_seen_at.present?
  end

  test "external id is unique" do
    record = SingleSignOnRecord.new(
      user: users(:jason),
      external_id: single_sign_on_records(:david).external_id
    )

    assert_not record.valid?
    assert_includes record.errors[:external_id], "has already been taken"
  end

  test "user is unique" do
    assert_raises ActiveRecord::RecordNotUnique do
      SingleSignOnRecord.insert!({ user_id: users(:david).id, external_id: "provider-david-2" })
    end
  end

  test "destroying user destroys sso record" do
    user = users(:david)
    record_id = single_sign_on_records(:david).id

    user.destroy!

    assert_not SingleSignOnRecord.exists?(record_id)
  end

  test "creates verified user and sso record for new verified email" do
    assert_difference -> { User.count }, +1 do
      assert_difference -> { SingleSignOnRecord.count }, +1 do
        record = SingleSignOnRecord.find_or_provision!(payload(email: "new@example.com", external_id: "new-1", name: "New User"))

        assert record.user.verified?
        assert_equal "New User", record.user.name
        assert_equal "new@example.com", record.user.email_address
        assert_equal "new-1", record.external_id
        assert_equal "new@example.com", record.external_email
      end
    end
  end

  test "updates audit fields for existing external id" do
    record = single_sign_on_records(:david)

    resolved_record = SingleSignOnRecord.find_or_provision!(payload(email: "david.changed@example.com", external_id: record.external_id))

    assert_equal record, resolved_record
    assert_equal users(:david), resolved_record.user
    assert_equal "david.changed@example.com", record.reload.external_email
    assert record.last_payload.include?("david.changed@example.com")
    assert_in_delta Time.current, record.last_seen_at, 2.seconds
  end

  test "refuses inactive users with existing external id" do
    user = users(:david)
    user.deactivate

    assert_raises Sso::Forbidden do
      SingleSignOnRecord.find_or_provision!(payload(email: user.email_address, external_id: single_sign_on_records(:david).external_id))
    end
  end

  test "claims existing email without sso record when activation is not required" do
    user = users(:jason)

    assert_difference -> { User.count }, 0 do
      assert_difference -> { SingleSignOnRecord.count }, +1 do
        record = SingleSignOnRecord.find_or_provision!(payload(email: user.email_address, external_id: "jason-provider"))

        assert_equal user, record.user
        assert_equal "jason-provider", user.single_sign_on_record.external_id
      end
    end
  end

  test "preserves local profile fields without override flags" do
    user = users(:david)

    SingleSignOnRecord.find_or_provision!(payload(
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

    SingleSignOnRecord.find_or_provision!(payload(
      email: user.email_address,
      external_id: single_sign_on_records(:david).external_id,
      name: "Provider Name",
      avatar_url: "https://example.com/provider.png"
    ))

    assert_equal "Provider Name", user.reload.name
    assert_equal "https://example.com/provider.png", user.avatar_url
  end

  test "rejects email claimed by another external id" do
    assert_raises Sso::Forbidden do
      SingleSignOnRecord.find_or_provision!(payload(email: users(:david).email_address, external_id: "attacker"))
    end
  end

  test "require activation does not claim existing email" do
    user = users(:jason)

    assert_no_difference -> { SingleSignOnRecord.count } do
      assert_raises Sso::ActivationRequired do
        SingleSignOnRecord.find_or_provision!(payload(email: user.email_address, external_id: "jason-provider", require_activation: true))
      end
    end
  end

  test "require activation creates unverified user and sends verification email" do
    assert_enqueued_emails 1 do
      assert_raises Sso::ActivationRequired do
        User.sign_in_with_sso!(payload(email: "activate@example.com", external_id: "activate-1", require_activation: true))
      end
    end

    user = User.find_by(email_address: "activate@example.com")
    assert_not user.verified?
    assert_equal "activate-1", user.single_sign_on_record.external_id
  end

  test "require activation for linked unverified user sends verification email without session" do
    user = users(:david)
    user.update!(verified_at: nil)

    assert_enqueued_emails 1 do
      assert_raises Sso::ActivationRequired do
        User.sign_in_with_sso!(payload(email: user.email_address, external_id: single_sign_on_records(:david).external_id, require_activation: true))
      end
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
