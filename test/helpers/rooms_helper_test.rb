require "test_helper"

class RoomsHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "room_type_indicator uses the message-log glyph for forums" do
    assert_includes room_type_indicator(rooms(:help_desk)), "icon--message-log"
  end

  test "room_type_indicator uses a hash for open rooms" do
    assert_equal "#", room_type_indicator(rooms(:hq))
  end

  test "room_type_indicator uses the lock glyph for closed rooms" do
    assert_includes room_type_indicator(rooms(:watercooler)), "icon--lock"
  end

  test "room_privacy_label explains open and private access" do
    assert_equal "Open to members", room_privacy_label(rooms(:hq))
    assert_equal "Private · invite only", room_privacy_label(rooms(:watercooler))
    assert_nil room_privacy_label(rooms(:help_desk))
  end

  test "edit_room_path resolves for a forum" do
    forum = rooms(:help_desk)
    assert_equal edit_rooms_forum_path(forum), edit_room_path(forum)
  end
end
