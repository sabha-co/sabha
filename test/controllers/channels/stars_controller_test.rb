require "test_helper"

class Channels::StarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create stars a channel" do
    membership = memberships(:david_designers)
    assert_not membership.starred?

    post channel_star_url(channels(:designers))
    assert membership.reload.starred?
  end

  test "destroy unstars a channel" do
    membership = memberships(:david_watercooler)
    assert membership.starred?

    delete channel_star_url(channels(:watercooler))
    assert_not membership.reload.starred?
  end

  test "create broadcasts remove from old section and append to new" do
    channel = channels(:designers)

    # 1 remove (from shared_channels) + 1 append (to starred_channels) = 2
    assert_turbo_stream_broadcasts [ users(:david), :channels ], count: 2 do
      post channel_star_url(channel)
    end

    assert_rendered_turbo_stream_broadcast users(:david), :channels, action: "remove",
      target: [ channel, "shared_channels_list_node" ]
    assert_rendered_turbo_stream_broadcast users(:david), :channels, action: "append", target: "starred_channels" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(channel, "starred_channels_list_node")}" do
        assert_select ".btn.star.starred", count: 1
      end
    end
  end

  test "destroy broadcasts remove from old section and append to new" do
    channel = channels(:watercooler)

    # 1 remove (from starred_channels) + 1 append (to shared_channels) = 2
    assert_turbo_stream_broadcasts [ users(:david), :channels ], count: 2 do
      delete channel_star_url(channel)
    end

    assert_rendered_turbo_stream_broadcast users(:david), :channels, action: "remove",
      target: [ channel, "starred_channels_list_node" ]
    assert_rendered_turbo_stream_broadcast users(:david), :channels, action: "append", target: "shared_channels" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(channel, "shared_channels_list_node")}" do
        assert_select ".btn.star", count: 1
        assert_select ".btn.star.starred", count: 0
      end
    end
  end

  test "cannot star a direct channel" do
    post channel_star_url(channels(:david_and_jason))
    assert_response :unprocessable_entity
    assert_not memberships(:david_david_and_jason).reload.starred?
  end

  test "cannot star an invisible membership" do
    memberships(:david_designers).update!(involvement: :invisible)

    post channel_star_url(channels(:designers))
    assert_response :unprocessable_entity
    assert_not memberships(:david_designers).reload.starred?
  end
end
