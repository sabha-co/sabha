require "test_helper"

class TaggingTest < ActiveSupport::TestCase
  setup do
    @forum = rooms(:help_desk)
    @tag = @forum.tags.create!(name: "Question")
    @post = create_forum_post
  end

  test "links a tag to a post" do
    tagging = Tagging.create!(tag: @tag, post: @post)

    assert_equal @tag, tagging.tag
    assert_equal @post, tagging.post
  end

  test "a post cannot carry the same tag twice" do
    Tagging.create!(tag: @tag, post: @post)
    dup = Tagging.new(tag: @tag, post: @post)

    assert_not dup.valid?
    assert dup.errors[:tag_id].present?
  end

  test "requires both a tag and a post" do
    assert_not Tagging.new.valid?
  end

  test "destroying a post deletes its taggings" do
    Tagging.create!(tag: @tag, post: @post)

    assert_difference -> { Tagging.count }, -1 do
      @post.destroy
    end
  end
end
