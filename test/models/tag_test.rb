require "test_helper"

class TagTest < ActiveSupport::TestCase
  setup do
    @forum = rooms(:help_desk)
  end

  test "a tag belongs to its forum" do
    tag = @forum.tags.create!(name: "Question", color: "#3366FF")

    assert_equal @forum, tag.forum
    assert_includes @forum.tags, tag
  end

  test "the same tag name may exist independently in two forums" do
    other = Rooms::Forum.create_for({ name: "Ideas", creator: users(:david) }, users: users(:david))
    here = @forum.tags.create!(name: "Bug")
    there = other.tags.create!(name: "Bug")

    assert here.persisted?
    assert there.persisted?
    assert_not_equal here.forum, there.forum
  end

  test "a tag name must be unique within a forum, case-insensitively" do
    @forum.tags.create!(name: "Setup")
    dup = @forum.tags.build(name: "setup")

    assert_not dup.valid?
    assert dup.errors[:name].present?
  end

  test "a tag cannot belong to a non-forum room" do
    tag = Tag.new(room_id: rooms(:hq).id, name: "Nope")

    assert_not tag.valid?
    assert tag.errors[:forum].present?
  end

  test "applying and removing a tag adds and removes a tagging row" do
    post = create_forum_post
    tag = @forum.tags.create!(name: "Question")

    assert_difference -> { Tagging.count }, 1 do
      post.tags << tag
    end
    assert_includes post.reload.tags, tag

    assert_difference -> { Tagging.count }, -1 do
      post.tags.destroy(tag)
    end
    assert_not_includes post.reload.tags, tag
  end

  test "deleting a tag used by posts removes its taggings and leaves the posts" do
    tag = @forum.tags.create!(name: "Question")
    post_one = create_forum_post(title: "First")
    post_two = create_forum_post(title: "Second")
    post_one.tags << tag
    post_two.tags << tag

    assert_difference -> { Tagging.count }, -2 do
      tag.destroy
    end
    assert Rooms::Thread.exists?(post_one.id)
    assert Rooms::Thread.exists?(post_two.id)
  end

  test "hard-deleting a forum destroys its tags and their taggings without FK violation" do
    tag = @forum.tags.create!(name: "Question")
    post = create_forum_post
    post.tags << tag
    tag_id = tag.id
    tagging_ids = post.taggings.pluck(:id)

    assert_nothing_raised { @forum.destroy }

    assert_not Tag.exists?(tag_id)
    assert_equal 0, Tagging.where(id: tagging_ids).count
  end
end
