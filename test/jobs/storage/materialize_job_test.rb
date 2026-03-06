require "test_helper"

class Storage::MaterializeJobTest < ActiveJob::TestCase
  setup do
    Sabha.stubs(:saas?).returns(true)
    @account = accounts(:signal)
  end

  test "calls materialize_storage on account" do
    Storage::Entry.record(delta: 1024, operation: "attach")

    Storage::MaterializeJob.perform_now(@account)

    assert_not_nil @account.storage_total
    assert_equal 1024, @account.bytes_used
  end

  test "job is idempotent" do
    Storage::Entry.record(delta: 1024, operation: "attach")

    3.times { Storage::MaterializeJob.perform_now(@account) }

    assert_equal 1024, @account.bytes_used
  end

  test "job processes entries added between runs" do
    Storage::Entry.record(delta: 1000, operation: "attach")
    Storage::MaterializeJob.perform_now(@account)

    Storage::Entry.record(delta: 500, operation: "attach")
    Storage::MaterializeJob.perform_now(@account)

    assert_equal 1500, @account.bytes_used
  end

  test "job queued to default queue" do
    assert_equal "default", Storage::MaterializeJob.new.queue_name
  end
end
