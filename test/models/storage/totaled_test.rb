require "test_helper"

class Storage::TotaledTest < ActiveSupport::TestCase
  setup do
    Sabha.stubs(:saas?).returns(true)
    @account = accounts(:signal)
  end

  # bytes_used (fast snapshot)

  test "bytes_used returns 0 when no storage_total exists" do
    assert_nil @account.storage_total
    assert_equal 0, @account.bytes_used
  end

  test "bytes_used returns snapshot value" do
    @account.create_storage_total!(bytes_stored: 10_000)
    assert_equal 10_000, @account.bytes_used
  end

  test "bytes_used does not include pending entries" do
    @account.create_storage_total!(bytes_stored: 1000)
    Storage::Entry.record(account: @account, delta: 500, operation: "attach")

    assert_equal 1000, @account.bytes_used
  end

  # bytes_used_exact (snapshot + pending)

  test "bytes_used_exact creates storage_total if missing" do
    assert_nil @account.storage_total
    @account.bytes_used_exact
    assert_not_nil @account.reload.storage_total
  end

  test "bytes_used_exact includes pending entries" do
    entry = Storage::Entry.record(account: @account, delta: 500, operation: "attach")
    @account.create_storage_total!(bytes_stored: 500, last_entry_id: entry.id)

    Storage::Entry.record(account: @account, delta: 256, operation: "attach")

    assert_equal 756, @account.bytes_used_exact
  end

  test "bytes_used_exact returns 0 when no entries and no snapshot" do
    assert_equal 0, @account.bytes_used_exact
  end

  # materialize_storage

  test "materialize_storage creates storage_total if missing" do
    assert_nil @account.storage_total

    Storage::Entry.record(account: @account, delta: 1024, operation: "attach")
    @account.materialize_storage

    total = @account.reload.storage_total
    assert_not_nil total
    assert_equal 1024, total.bytes_stored
  end

  test "materialize_storage processes all pending entries" do
    Storage::Entry.record(account: @account, delta: 1000, operation: "attach")
    Storage::Entry.record(account: @account, delta: 2000, operation: "attach")
    Storage::Entry.record(account: @account, delta: -500, operation: "detach")

    @account.materialize_storage

    assert_equal 2500, @account.storage_total.bytes_stored
    assert_equal 0, @account.storage_total.pending_entries.count
  end

  test "materialize_storage updates cursor to latest entry" do
    Storage::Entry.record(account: @account, delta: 1000, operation: "attach")
    entry2 = Storage::Entry.record(account: @account, delta: 500, operation: "attach")

    @account.materialize_storage

    assert_equal entry2.id, @account.storage_total.last_entry_id
  end

  test "materialize_storage is idempotent when no new entries" do
    Storage::Entry.record(account: @account, delta: 1000, operation: "attach")
    @account.materialize_storage

    initial_bytes = @account.storage_total.bytes_stored
    initial_cursor = @account.storage_total.last_entry_id

    @account.materialize_storage

    assert_equal initial_bytes, @account.storage_total.bytes_stored
    assert_equal initial_cursor, @account.storage_total.last_entry_id
  end

  test "materialize_storage processes only entries since cursor" do
    Storage::Entry.record(account: @account, delta: 1000, operation: "attach")
    @account.materialize_storage

    assert_equal 1000, @account.storage_total.bytes_stored

    Storage::Entry.record(account: @account, delta: 500, operation: "attach")
    @account.materialize_storage

    assert_equal 1500, @account.storage_total.bytes_stored
  end

  test "materialize_storage does nothing when no entries" do
    @account.materialize_storage

    total = @account.reload.storage_total
    assert_not_nil total
    assert_equal 0, total.bytes_stored
    assert_nil total.last_entry_id
  end

  # reconcile_storage

  test "reconcile_storage creates entry for drift" do
    message = messages(:first)
    message.attachment.attach io: StringIO.new("x" * 1000), filename: "test.png", content_type: "image/png"

    Storage::Entry.delete_all

    assert_difference "Storage::Entry.count", +1 do
      @account.reconcile_storage
    end

    entry = Storage::Entry.find_by(operation: "reconcile")
    assert_equal 1000, entry.delta
  end

  test "reconcile_storage no-op when ledger matches reality" do
    message = messages(:first)
    message.attachment.attach io: StringIO.new("x" * 1000), filename: "test.png", content_type: "image/png"

    assert_no_difference "Storage::Entry.where(operation: 'reconcile').count" do
      @account.reconcile_storage
    end
  end

  test "reconcile_storage handles negative drift" do
    Storage::Entry.create! \
      delta: 5000,
      operation: "attach"

    @account.reconcile_storage

    entry = Storage::Entry.find_by(operation: "reconcile")
    assert_not_nil entry
    assert_equal(-5000, entry.delta)
  end

  test "reconcile_storage aborts when entry added during scan" do
    message = messages(:first)
    message.attachment.attach io: StringIO.new("x" * 1000), filename: "test.png", content_type: "image/png"

    Storage::Entry.delete_all

    @account.define_singleton_method(:calculate_real_storage_bytes) do
      Storage::Entry.create!(delta: 500, operation: "attach")
      super()
    end

    assert_no_difference "Storage::Entry.where(operation: 'reconcile').count" do
      result = @account.reconcile_storage
      assert_equal false, result
    end
  end
end
