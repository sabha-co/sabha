require "test_helper"

class ChannelsHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "channel_type_indicator uses the message-log glyph for forums" do
    assert_includes channel_type_indicator(channels(:help_desk)), "icon--message-log"
  end

  test "channel_type_indicator uses a hash for open channels" do
    assert_equal "#", channel_type_indicator(channels(:hq))
  end

  test "channel_type_indicator uses the lock glyph for closed channels" do
    assert_includes channel_type_indicator(channels(:watercooler)), "icon--lock"
  end

  test "edit_channel_path resolves for a forum" do
    forum = channels(:help_desk)
    assert_equal edit_channels_forum_path(forum), edit_channel_path(forum)
  end
end
