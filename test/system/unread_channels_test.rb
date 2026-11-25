require "application_system_test_case"

class UnreadChannelsTest < ApplicationSystemTestCase
  setup do
    sign_in "jz@37signals.com"
  end

  test "channel shows as unread when another user sends messages" do
    designers_channel = channels(:designers)
    hq_channel = channels(:hq)

    join_channel hq_channel
    assert_channel_read hq_channel

    using_session("Kevin") do
      sign_in "kevin@37signals.com"
      join_channel designers_channel
      send_message("Hello!!")
      send_message("Talking to myself?")
    end

    assert_channel_unread designers_channel

    join_channel designers_channel
    assert_channel_read designers_channel
  end
end
