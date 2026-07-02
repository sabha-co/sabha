require "test_helper"

class Rooms::Forums::TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @forum = Rooms::Forum.create_for({ name: "Help Desk", creator: users(:david) }, users: [ users(:david), users(:kevin) ])
  end

  test "admin creates a tag scoped to the forum" do
    assert_difference -> { @forum.tags.count }, 1 do
      post rooms_forum_tags_url(@forum), params: { tag: { name: "Question", color: "#3366FF" } }
    end

    assert_redirected_to edit_rooms_forum_url(@forum)
    assert_equal @forum.id, @forum.tags.last.room_id
  end

  test "a duplicate tag name within a forum is rejected with an alert" do
    @forum.tags.create!(name: "Question")

    assert_no_difference -> { @forum.tags.count } do
      post rooms_forum_tags_url(@forum), params: { tag: { name: "question" } }
    end

    assert_redirected_to edit_rooms_forum_url(@forum)
    assert_equal "Name has already been taken", flash[:alert]
  end

  test "admin deletes a tag" do
    tag = @forum.tags.create!(name: "Question")

    assert_difference -> { @forum.tags.count }, -1 do
      delete rooms_forum_tag_url(@forum, tag)
    end
  end

  test "a non-admin non-creator cannot curate tags" do
    sign_in :kevin

    assert_no_difference -> { @forum.tags.count } do
      post rooms_forum_tags_url(@forum), params: { tag: { name: "Sneaky" } }
    end

    assert_response :forbidden
  end
end
