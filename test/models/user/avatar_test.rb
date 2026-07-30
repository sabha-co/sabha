require "test_helper"

class User::AvatarTest < ActiveSupport::TestCase
  test "avatar with allowed content type is valid" do
    user = users(:david)
    user.avatar.attach(
      io: StringIO.new("fake jpg"), filename: "photo.jpg", content_type: "image/jpeg"
    )

    assert user.valid?
  end

  test "avatar with disallowed content type is invalid" do
    user = users(:david)
    user.avatar.attach(
      io: StringIO.new("not an image"), filename: "doc.pdf", content_type: "application/pdf"
    )

    assert_not user.valid?
    assert_includes user.errors[:avatar], "must be a JPEG, PNG, GIF, or WebP image"
  end

  test "avatar_variant resizes a variable avatar" do
    user = users(:david)
    user.avatar.attach io: file_fixture("moon.jpg").open, filename: "moon.jpg", content_type: "image/jpeg"

    assert_kind_of ActiveStorage::VariantWithRecord, user.avatar_variant
  end

  test "avatar_variant is nil without an avatar" do
    assert_nil users(:kevin).avatar_variant
  end

  # The content type validation only sees the uploader's claim; libvips picks its loader from the
  # bytes, and refuses the ones whose only loader is unfuzzed.
  test "avatar_variant is nil when the bytes are not the declared image type" do
    user = users(:david)
    user.avatar.attach io: file_fixture("pixel.bmp").open, filename: "pixel.png", content_type: "image/png"

    assert_nil user.avatar_variant
  end
end
