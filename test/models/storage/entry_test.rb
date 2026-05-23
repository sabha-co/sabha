require "test_helper"

class Storage::EntryTest < ActiveSupport::TestCase
  setup do
    Sabha.stubs(:saas?).returns(true)
    @account = accounts(:signal)
    @message = messages(:first)
  end

  test "record creates entry with positive delta" do
    assert_difference "Storage::Entry.count", +1 do
      entry = Storage::Entry.record \
        account: @account,
        recordable: @message,
        delta: 1024,
        operation: "attach"

      assert_equal @message.class.name, entry.recordable_type
      assert_equal @message.id, entry.recordable_id
      assert_equal 1024, entry.delta
      assert_equal "attach", entry.operation
    end
  end

  test "record creates entry with negative delta" do
    entry = Storage::Entry.record \
      account: @account,
      recordable: @message,
      delta: -512,
      operation: "detach"

    assert_equal(-512, entry.delta)
    assert_equal "detach", entry.operation
  end

  test "record returns nil and creates no entry when delta is zero" do
    assert_no_difference "Storage::Entry.count" do
      result = Storage::Entry.record \
        account: @account,
        recordable: @message,
        delta: 0,
        operation: "attach"

      assert_nil result
    end
  end

  test "record creates entry without recordable" do
    entry = Storage::Entry.record \
      account: @account,
      recordable: nil,
      delta: 1024,
      operation: "reconcile"

    assert_nil entry.recordable_type
    assert_nil entry.recordable_id
  end

  test "record captures Current.user and Current.request_id when present" do
    user = users(:david)
    request = ActionDispatch::Request.new("action_dispatch.request_id" => "req-123")

    Current.set(user: user, request: request) do
      entry = Storage::Entry.record \
        account: @account,
        delta: 1024,
        operation: "attach"

      assert_equal user.id, entry.user_id
      assert_equal "req-123", entry.request_id
    end
  end

  test "record enqueues MaterializeJob for account" do
    assert_enqueued_with job: Storage::MaterializeJob, args: [ @account ] do
      Storage::Entry.record \
        account: @account,
        delta: 1024,
        operation: "attach"
    end
  end

  test "record skips when not in SaaS mode" do
    Sabha.stubs(:saas?).returns(false)

    assert_no_difference "Storage::Entry.count" do
      result = Storage::Entry.record \
        account: @account,
        delta: 1024,
        operation: "attach"

      assert_nil result
    end
  end

  test "suppressing_recording skips entry creation inside block" do
    assert_no_difference "Storage::Entry.count" do
      result = Storage::Entry.suppressing_recording do
        Storage::Entry.record account: @account, delta: 1024, operation: "attach"
      end

      assert_nil result
    end

    assert Storage::Entry.recording, "recording flag must be restored after the block"
  end

  test "suppressing_recording restores the flag even when the block raises" do
    assert_raises(RuntimeError) do
      Storage::Entry.suppressing_recording { raise "boom" }
    end

    assert Storage::Entry.recording
  end
end
