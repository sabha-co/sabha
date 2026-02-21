require "test_helper"

class DirectUploadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "once.sabha.test"
  end

  test "unauthenticated request is rejected" do
    post rails_direct_uploads_url, params: {
      blob: { filename: "test.png", byte_size: 123, checksum: "abc", content_type: "image/png" }
    }, as: :json

    assert_response :unauthorized
  end

  test "authenticated request succeeds" do
    sign_in :david

    checksum = OpenSSL::Digest::MD5.base64digest("fake data")

    post rails_direct_uploads_url, params: {
      blob: { filename: "test.png", byte_size: 9, checksum: checksum, content_type: "image/png" }
    }, as: :json

    assert_response :success
    assert_includes response.parsed_body.keys, "signed_id"
  end
end
