require "test_helper"

class Account::StorageTest < ActiveSupport::TestCase
  setup do
    Sabha.stubs(:saas?).returns(true)
    @account = accounts(:signal)
  end

  test "exceeding_storage_limit? returns false when under limit" do
    @account.create_storage_total!(bytes_stored: 500.megabytes)
    assert_not @account.exceeding_storage_limit?
  end

  test "exceeding_storage_limit? returns true when over limit" do
    @account.create_storage_total!(bytes_stored: 1.1.gigabytes.to_i)
    assert @account.exceeding_storage_limit?
  end

  test "exceeding_storage_limit? returns true when exactly at limit" do
    @account.create_storage_total!(bytes_stored: 1.gigabyte)
    assert @account.exceeding_storage_limit?
  end

  test "nearing_storage_limit? returns true when within 100MB of limit" do
    @account.create_storage_total!(bytes_stored: 950.megabytes.to_i)
    assert @account.nearing_storage_limit?
  end

  test "nearing_storage_limit? returns false when well under limit" do
    @account.create_storage_total!(bytes_stored: 500.megabytes)
    assert_not @account.nearing_storage_limit?
  end

  test "storage_percentage_used calculates correctly" do
    @account.create_storage_total!(bytes_stored: 512.megabytes.to_i)
    assert_equal 50, @account.storage_percentage_used
  end

  test "storage_percentage_used caps at 100" do
    @account.create_storage_total!(bytes_stored: 2.gigabytes.to_i)
    assert_equal 100, @account.storage_percentage_used
  end

  test "calculate_real_storage_bytes counts message attachments" do
    message = messages(:first)
    message.attachment.attach io: StringIO.new("x" * 2048), filename: "test.png", content_type: "image/png"

    assert_equal 2048, @account.send(:calculate_real_storage_bytes)
  end

  test "calculate_real_storage_bytes excludes avatars" do
    user = users(:david)
    user.avatar.attach io: StringIO.new("x" * 1024), filename: "avatar.png", content_type: "image/png"

    assert_equal 0, @account.send(:calculate_real_storage_bytes)
  end
end
