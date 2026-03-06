require "test_helper"

class Storage::AttachmentTrackingTest < ActiveSupport::TestCase
  setup do
    Sabha.stubs(:saas?).returns(true)
    @account = accounts(:signal)
    @message = messages(:first)
  end

  # Attachment Creation

  test "attaching file creates storage entry with positive delta" do
    assert_difference "Storage::Entry.count", +1 do
      @message.attachment.attach io: StringIO.new("x" * 2048), filename: "test.png", content_type: "image/png"
    end

    entry = Storage::Entry.last
    assert_equal 2048, entry.delta
    assert_equal "attach", entry.operation
    assert_equal @message.class.name, entry.recordable_type
    assert_equal @message.id, entry.recordable_id
    assert_equal @message.attachment.blob.id, entry.blob_id
  end

  test "attaching file enqueues MaterializeJob for account" do
    assert_enqueued_with job: Storage::MaterializeJob, args: [ @account ] do
      @message.attachment.attach io: StringIO.new("x" * 1024), filename: "test.png", content_type: "image/png"
    end
  end

  # Attachment Deletion

  test "destroying attachment creates storage entry with negative delta" do
    @message.attachment.attach io: StringIO.new("x" * 2048), filename: "test.png", content_type: "image/png"
    attachment = @message.attachment.attachment
    blob_id = attachment.blob_id

    attachment.destroy!

    entry = Storage::Entry.find_by(operation: "detach", recordable: @message)
    assert_not_nil entry, "Expected detach entry to be created"
    assert_equal(-2048, entry.delta)
    assert_equal "detach", entry.operation
    assert_equal blob_id, entry.blob_id
  end

  test "destroying attachment uses snapshotted IDs from before_destroy" do
    @message.attachment.attach io: StringIO.new("x" * 1024), filename: "test.png", content_type: "image/png"

    expected_recordable_type = @message.class.name
    expected_recordable_id = @message.id

    attachment = @message.attachment.attachment
    attachment.destroy!

    entry = Storage::Entry.find_by(operation: "detach", recordable_id: expected_recordable_id)
    assert_not_nil entry, "Expected detach entry to be created"
    assert_equal expected_recordable_type, entry.recordable_type
    assert_equal expected_recordable_id, entry.recordable_id
  end

  # Non-Trackable Records

  test "does not track attachments on non-trackable records" do
    Sabha.stubs(:saas?).returns(true)
    user = users(:david)

    assert_no_difference "Storage::Entry.count" do
      user.avatar.attach io: StringIO.new("x" * 1024), filename: "avatar.png", content_type: "image/png"
    end
  end

  # Edge Cases

  test "replacing attachment creates detach and attach entries" do
    @message.attachment.attach io: StringIO.new("x" * 1024), filename: "first.png", content_type: "image/png"

    @message.attachment.attach io: StringIO.new("x" * 2048), filename: "second.png", content_type: "image/png"

    entries = Storage::Entry.where(recordable: @message).order(:id).last(2)
    attach_entry = entries.find { |e| e.operation == "attach" && e.delta == 2048 }
    assert_not_nil attach_entry
  end

  # Cascading Deletes

  test "attachment tracking handles message deletion gracefully" do
    @message.attachment.attach io: StringIO.new("x" * 1024), filename: "test.png", content_type: "image/png"
    message_id = @message.id

    perform_enqueued_jobs do
      assert_nothing_raised do
        @message.destroy!
      end
    end

    detach_entry = Storage::Entry.find_by(recordable_id: message_id, operation: "detach")
    assert_not_nil detach_entry, "Expected detach entry for destroyed message"
    assert_equal(-1024, detach_entry.delta)
  end
end
