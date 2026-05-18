require "test_helper"

class SingleSignOnRecordTest < ActiveSupport::TestCase
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
    record = SingleSignOnRecord.new(
      user: users(:david),
      external_id: "provider-david-2"
    )

    assert_not record.valid?
    assert_includes record.errors[:user_id], "has already been taken"
  end

  test "destroying user destroys sso record" do
    user = users(:david)
    record_id = single_sign_on_records(:david).id

    user.destroy!

    assert_not SingleSignOnRecord.exists?(record_id)
  end
end
