require "test_helper"

# Naming RoomStreamsChannel in the view only changes what honest clients do — the
# subscriber picks the channel in its subscribe frame. So the stock channel has to
# turn room stream names away itself, or the authorization there is decorative.
class TurboStreamsChannelAuthorizationTest < ActionCable::Channel::TestCase
  tests Turbo::StreamsChannel

  test "a room's message stream can't be reached through the stock channel" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ rooms(:designers), :messages ])

    assert subscription.rejected?, "even a member has to come through RoomStreamsChannel"
  end

  test "a forum's post stream can't be reached through the stock channel" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ rooms(:help_desk), :posts ])

    assert subscription.rejected?
  end

  test "the sidebar's room stream still works on the stock channel" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ users(:kevin), :rooms ])

    assert subscription.confirmed?
  end

  test "a membership stream still works on the stock channel" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name(memberships(:kevin_designers))

    assert subscription.confirmed?
  end
end
