require "test_helper"

class Users::AvatarsHelperTest < ActionView::TestCase
  include Users::AvatarsHelper

  setup do
    @user = users(:kevin)
    @bot = users(:bender)
  end

  # user_image_path - now always goes through controller

  test "user_image_path returns controller path for user without avatar" do
    path = user_image_path(@user)
    # Should return a signed avatar path that goes through the controller
    assert_match %r{/users/.+/avatar}, path
  end

  test "user_image_path returns avatar_url when present" do
    user_with_url = User.new(id: 999, name: "Test", avatar_url: "https://example.com/avatar.png")
    path = user_image_path(user_with_url)
    assert_equal "https://example.com/avatar.png", path
  end

  # avatar_image_tag

  test "avatar_image_tag renders image with controller path" do
    html = avatar_image_tag(@user)
    assert_match %r{<img[^>]+src="/users/.+/avatar}, html
    assert_match %r{loading="lazy"}, html
    assert_match %r{aria-hidden="true"}, html
  end

  test "avatar_image_tag passes options to image tag" do
    html = avatar_image_tag(@user, size: 100, class: "custom-class")
    assert_match %r{width="100"}, html
    assert_match %r{height="100"}, html
    assert_match %r{class="custom-class"}, html
  end
end
