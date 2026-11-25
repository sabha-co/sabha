require "test_helper"

class Channels::InvolvementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show renders the involvement turbo frame for the channel" do
    get channel_involvement_url(channels(:designers))

    assert_response :success
    assert_select "turbo-frame##{dom_id(channels(:designers), :involvement)}"
  end

  test "update involvement sends turbo update when going invisible" do
    streams = capture_turbo_stream_broadcasts [ users(:david), :channels ] do
      assert_changes -> { memberships(:david_watercooler).reload.involvement }, from: "everything", to: "invisible" do
        put channel_involvement_url(channels(:watercooler)), params: { involvement: "invisible" }
        assert_redirected_to channel_involvement_url(channels(:watercooler))
      end
    end

    # 1 broadcast for sidebar section + 2 for removal + 1 for hidden_channels append
    assert_equal 4, streams.size

    append = streams.find { |stream| stream["action"] == "append" }
    assert append, "going invisible should append the channel into the hidden-channels list"
    assert_equal "hidden_channels_list", append["target"],
      "the append must target the hidden-channels list id rendered by users/hidden_channels/index"
    assert append.at_css("##{dom_id(channels(:watercooler), :hidden_channel)}"),
      "the append carries the hidden-channel row for the newly invisible channel"
  end

  test "update involvement sends turbo update when returning to visible" do
    # First make it invisible
    memberships(:david_watercooler).update!(involvement: "invisible")

    # When returning to visible: 1 broadcast for sidebar section + 1 for append + 1 for hidden_channels removal = 3
    assert_turbo_stream_broadcasts [ users(:david), :channels ], count: 3 do
    assert_changes -> { memberships(:david_watercooler).reload.involvement }, from: "invisible", to: "everything" do
      put channel_involvement_url(channels(:watercooler)), params: { involvement: "everything" }
      assert_redirected_to channel_involvement_url(channels(:watercooler))
    end
    end
  end

  test "updating involvement does not send extra turbo update when changing between visible states" do
    # 1 broadcast for the correct sidebar section (starred_channels or shared_channels)
    assert_turbo_stream_broadcasts [ users(:david), :channels ], count: 1 do
    assert_changes -> { memberships(:david_watercooler).reload.involvement }, from: "everything", to: "mentions" do
      put channel_involvement_url(channels(:watercooler)), params: { involvement: "mentions" }
      assert_redirected_to channel_involvement_url(channels(:watercooler))
    end
    end
  end

  test "updating involvement does not send extra turbo update for direct channels" do
    # Direct channels skip sidebar broadcasts entirely
    assert_turbo_stream_broadcasts [ users(:david), :channels ], count: 0 do
    assert_changes -> { memberships(:david_david_and_jason).reload.involvement }, from: "everything", to: "nothing" do
      put channel_involvement_url(channels(:david_and_jason)), params: { involvement: "nothing" }
      assert_redirected_to channel_involvement_url(channels(:david_and_jason))
    end
    end
  end

  test "update honors a same-origin return_to" do
    put channel_involvement_url(channels(:watercooler)),
        params: { involvement: "mentions", return_to: "/channels/#{channels(:watercooler).id}" }

    assert_redirected_to "/channels/#{channels(:watercooler).id}"
  end

  test "update rejects a cross-origin return_to and falls back to the channel involvement" do
    put channel_involvement_url(channels(:watercooler)),
        params: { involvement: "mentions", return_to: "https://evil.example.com/steal" }

    assert_redirected_to channel_involvement_url(channels(:watercooler))
  end
end
