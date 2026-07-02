require "test_helper"

class RoomsHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "room_type_indicator uses the board glyph for forums" do
    assert_includes room_type_indicator(rooms(:help_desk)), "icon--board"
  end

  test "room_type_indicator uses a hash for open rooms" do
    assert_equal "#", room_type_indicator(rooms(:hq))
  end

  test "room_type_indicator uses the lock glyph for closed rooms" do
    assert_includes room_type_indicator(rooms(:watercooler)), "icon--lock"
  end

  test "edit_room_path resolves for a forum" do
    forum = rooms(:help_desk)
    assert_equal edit_rooms_forum_path(forum), edit_room_path(forum)
  end
end
