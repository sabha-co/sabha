require "test_helper"

class ActiveStorageAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    host! "once.sabha.test"

    @blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("hello"), filename: "test.txt", content_type: "text/plain"
    )
  end

  test "unauthenticated blob access is rejected" do
    get rails_blob_url(@blob)
    assert_response :unauthorized
  end

  test "authenticated blob access succeeds" do
    sign_in :david

    get rails_blob_url(@blob)
    assert_response :redirect
  end

  test "unauthenticated representation access is rejected" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("moon.jpg").open, filename: "moon.jpg", content_type: "image/jpeg"
    )
    variation = ActiveStorage::Variation.encode(resize_to_limit: [ 100, 100 ])

    get rails_blob_representation_url(blob.signed_id, variation, blob.filename)
    assert_response :unauthorized
  end

  test "avatar access works without authentication" do
    user = users(:david)
    user.avatar.attach(
      io: file_fixture("moon.jpg").open, filename: "avatar.jpg", content_type: "image/jpeg"
    )

    get fresh_user_avatar_url(user)
    assert_response :success
  end
end
