require "test_helper"

class ActiveStorageDirectUploadExpiryTest < ActiveSupport::TestCase
  setup do
    @blob = ActiveStorage::Blob.new(key: "test", filename: "test.txt", byte_size: 1024, checksum: "abc")
  end

  test "uses 1-hour expiry by default" do
    # Stub only the inner SDK boundary so the prepended module actually runs.
    # We capture the kwargs the storage service receives to prove the patch's
    # 1-hour default flows through to `service.url_for_direct_upload`.
    captured_kwargs = nil
    @blob.service.define_singleton_method(:url_for_direct_upload) do |_key, **kwargs|
      captured_kwargs = kwargs
      "https://example.com/upload"
    end

    assert_equal "https://example.com/upload", @blob.service_url_for_direct_upload
    assert_equal 1.hour, captured_kwargs[:expires_in]
  end
end
