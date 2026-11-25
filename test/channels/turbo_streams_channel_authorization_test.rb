require "test_helper"

# Naming ChannelStreamsChannel in the view only changes what honest clients do — the
# subscriber picks the channel in its subscribe frame. So the stock channel has to
# turn channel stream names away itself, or the authorization there is decorative.
class TurboStreamsChannelAuthorizationTest < ActionCable::Channel::TestCase
  tests Turbo::StreamsChannel

  test "a channel's message stream can't be reached through the stock channel" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ channels(:designers), :messages ])

    assert subscription.rejected?, "even a member has to come through ChannelStreamsChannel"
  end

  test "a forum's post stream can't be reached through the stock channel" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ channels(:help_desk), :posts ])

    assert subscription.rejected?
  end

  test "the sidebar's channel stream still works on the stock channel" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ users(:kevin), :channels ])

    assert subscription.confirmed?
  end

  test "a membership stream still works on the stock channel" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name(memberships(:kevin_designers))

    assert subscription.confirmed?
  end

  test "the account-wide channel stream still works on the stock channel" do
    stub_connection current_user: users(:kevin)

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ accounts(:signal), :channels ])

    assert subscription.confirmed?
  end
end
