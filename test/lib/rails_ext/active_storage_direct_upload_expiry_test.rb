require "test_helper"

class ActiveStorageDirectUploadExpiryTest < ActiveSupport::TestCase
  setup do
    @blob = ActiveStorage::Blob.new(key: "test", filename: "test.txt", byte_size: 1024, checksum: "abc")
  end

  test "uses 1-hour expiry by default" do
    @blob.service.expects(:url_for_direct_upload).with(
      @blob.key,
      expires_in: 1.hour,
      content_type: @blob.content_type,
      content_length: @blob.byte_size,
      checksum: @blob.checksum,
      custom_metadata: {}
    ).returns("https://example.com/upload")

    assert_equal "https://example.com/upload", @blob.service_url_for_direct_upload
  end
end
