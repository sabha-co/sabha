require "test_helper"

class Storage::ReconcileJobTest < ActiveJob::TestCase
  setup do
    Sabha.stubs(:saas?).returns(true)
    @account = accounts(:signal)
    @message = messages(:first)
  end

  test "reconcile corrects drift when ledger undercounts" do
    @message.attachment.attach io: StringIO.new("x" * 1000), filename: "test.png", content_type: "image/png"
    Storage::Entry.delete_all

    Storage::ReconcileJob.perform_now(@account)

    entry = Storage::Entry.find_by(operation: "reconcile")
    assert_not_nil entry
    assert_equal 1000, entry.delta
  end

  test "reconcile corrects drift when ledger overcounts" do
    Storage::Entry.create! \
      delta: 5000,
      operation: "attach"

    Storage::ReconcileJob.perform_now(@account)

    entry = Storage::Entry.find_by(operation: "reconcile")
    assert_not_nil entry
    assert_equal(-5000, entry.delta)
  end

  test "reconcile creates no entry when ledger matches reality" do
    @message.attachment.attach io: StringIO.new("x" * 1000), filename: "test.png", content_type: "image/png"

    assert_no_difference "Storage::Entry.where(operation: 'reconcile').count" do
      Storage::ReconcileJob.perform_now(@account)
    end
  end

  test "job raises ReconcileAborted when reconcile fails" do
    # Trigger the real cursor-drift failure path: a Storage::Entry written
    # mid-scan moves the cursor between the before/after snapshots in
    # Storage::Totaled#reconcile_storage, which then returns false and the
    # job raises ReconcileAborted.
    @account.define_singleton_method(:calculate_real_storage_bytes) do
      Storage::Entry.create!(delta: 1, operation: "attach")
      0
    end

    assert_raises Storage::ReconcileJob::ReconcileAborted do
      Storage::ReconcileJob.new.perform(@account)
    end
  end
end
