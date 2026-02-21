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
end
