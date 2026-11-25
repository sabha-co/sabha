require "test_helper"

class Channels::InvolvementSettingsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  # Mute toggle tests for shared channels
  test "mute toggle on shared channel sets involvement to nothing" do
    channel = channels(:hq)
    membership = memberships(:david_hq)
    assert membership.involved_in_everything?

    put channel_involvement_url(channel), params: { involvement: "nothing", return_to: edit_channel_path(channel) }

    assert membership.reload.involved_in_nothing?
  end

  test "unmute toggle on shared channel sets involvement to mentions" do
    channel = channels(:hq)
    membership = memberships(:david_hq)
    membership.update!(involvement: "nothing")

    put channel_involvement_url(channel), params: { involvement: "mentions", return_to: edit_channel_path(channel) }

    assert membership.reload.involved_in_mentions?
  end

  # Mute toggle tests for direct channels
  test "mute toggle on direct channel sets involvement to nothing" do
    channel = channels(:david_and_jason)
    membership = memberships(:david_david_and_jason)
    assert membership.involved_in_everything?

    put channel_involvement_url(channel), params: { involvement: "nothing", return_to: edit_channels_direct_path(channel) }

    assert membership.reload.involved_in_nothing?
  end

  test "unmute toggle on direct channel sets involvement to everything" do
    channel = channels(:david_and_jason)
    membership = memberships(:david_david_and_jason)
    membership.update!(involvement: "nothing")

    put channel_involvement_url(channel), params: { involvement: "everything", return_to: edit_channels_direct_path(channel) }

    assert membership.reload.involved_in_everything?
  end

  # Hide toggle tests for shared channels
  test "hide toggle on shared channel sets involvement to invisible" do
    channel = channels(:hq)
    membership = memberships(:david_hq)

    assert_turbo_stream_broadcasts [ users(:david), :channels ], count: 4 do
      put channel_involvement_url(channel), params: { involvement: "invisible", return_to: edit_channel_path(channel) }
    end

    assert membership.reload.involved_in_invisible?
  end

  test "unhide toggle on shared channel sets involvement to mentions" do
    channel = channels(:hq)
    membership = memberships(:david_hq)
    membership.update!(involvement: "invisible")

    assert_turbo_stream_broadcasts [ users(:david), :channels ], count: 3 do
      put channel_involvement_url(channel), params: { involvement: "mentions", return_to: edit_channel_path(channel) }
    end

    assert membership.reload.involved_in_mentions?
  end

  # Return_to parameter tests
  test "returns to specified path after update" do
    channel = channels(:hq)

    put channel_involvement_url(channel), params: { involvement: "nothing", return_to: edit_channel_path(channel) }

    assert_redirected_to edit_channel_path(channel)
  end

  test "turbo stream request returns head ok" do
    channel = channels(:hq)

    put channel_involvement_url(channel), params: { involvement: "nothing" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
  end

  # Combined state tests
  test "muted and then hidden channel is invisible" do
    channel = channels(:hq)
    membership = memberships(:david_hq)

    # First mute
    put channel_involvement_url(channel), params: { involvement: "nothing" }
    assert membership.reload.involved_in_nothing?

    # Then hide
    put channel_involvement_url(channel), params: { involvement: "invisible" }
    assert membership.reload.involved_in_invisible?
  end

  test "hidden channel when unhidden returns to base involvement not nothing" do
    channel = channels(:hq)
    membership = memberships(:david_hq)

    # Hide the channel
    membership.update!(involvement: "invisible")

    # Unhide should go to mentions (base for shared channels), not nothing
    put channel_involvement_url(channel), params: { involvement: "mentions" }
    assert membership.reload.involved_in_mentions?
  end
end
