require "test_helper"

class Channels::ClosedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show redirects to get general show" do
    get channels_open_url(users(:david).channels.closeds.last)
    assert_redirected_to channel_url(users(:david).channels.closeds.last)
  end

  test "new" do
    get new_channels_closed_url
    assert_response :success
  end

  test "create" do
    # Only creator is added; 1 broadcast to the correct sidebar section
    assert_turbo_stream_broadcasts [ users(:david), :channels ], count: 1 do
      post channels_closeds_url, params: { channel: { name: "My New Channel" } }
    end

    new_channel = Channel.last
    assert_equal 1, new_channel.memberships.count
    assert_redirected_to edit_channels_closed_url(new_channel, tab: "members")
  end

  test "update channel name" do
    put channels_closed_url(channels(:designers)), params: { channel: { name: "New Name" } }

    assert_redirected_to channel_url(channels(:designers))
    assert_equal "New Name", channels(:designers).reload.name
  end

  test "only admins or creators can update" do
    sign_in :jz

    assert_turbo_stream_broadcasts [ accounts(:signal), :channels ], count: 0 do
      put channels_closed_url(channels(:designers)), params: { channel: { name: "New Name" } }
    end

    assert_response :forbidden
    assert channels(:designers).reload.name, "Designers"
  end


  test "non-admin cannot create channel when restricted to administrators" do
    accounts(:signal).settings.restrict_channel_creation_to_administrators = true
    accounts(:signal).save!

    sign_in :jz  # non-admin user

    get new_channels_closed_url
    assert_response :forbidden

    post channels_closeds_url, params: { channel: { name: "My New Channel" } }
    assert_response :forbidden
  end

  test "admin can create channel when restricted to administrators" do
    accounts(:signal).settings.restrict_channel_creation_to_administrators = true
    accounts(:signal).save!

    sign_in :david  # admin user

    get new_channels_closed_url
    assert_response :success

    post channels_closeds_url, params: { channel: { name: "Admin Channel" } }
    assert_redirected_to edit_channels_closed_url(Channel.last, tab: "members")
  end

  # Event messages

  test "update posts rename event when name changes" do
    channel = channels(:designers)

    assert_difference -> { Message.unscoped.where(channel: channel, event: "channel_renamed").count } do
      put channels_closed_url(channel), params: { channel: { name: "New Designers" } }
    end

    event = Message.unscoped.where(channel: channel, event: "channel_renamed").last
    assert_equal "renamed the channel from Designers to New Designers", event.reload.plain_text_body
  end

  test "update does not post events when nothing changes" do
    channel = channels(:designers)

    assert_no_difference -> { Message.unscoped.where(channel: channel).where.not(event: nil).count } do
      put channels_closed_url(channel), params: { channel: { name: channel.name } }
    end
  end

  # Destroy permission tests

  test "admin can destroy any closed channel" do
    sign_in :david

    assert_difference -> { Channel.active.count }, -1 do
      delete channels_closed_url(channels(:designers))
    end

    assert_redirected_to root_url
  end

  test "creator can destroy their own closed channel" do
    sign_in :kevin
    post channels_closeds_url, params: { channel: { name: "Kevin's Private Channel" } }
    channel = Channel.last

    assert_difference -> { Channel.active.count }, -1 do
      delete channels_closed_url(channel)
    end

    assert_redirected_to root_url
  end

  test "non-admin non-creator cannot destroy closed channel" do
    sign_in :jz

    assert_no_difference -> { Channel.active.count } do
      delete channels_closed_url(channels(:designers))
    end

    assert_response :forbidden
  end

  # Tabbed edit layout

  test "edit renders tabbed layout with three tabs" do
    get edit_channels_closed_url(channels(:designers))
    assert_response :success
    assert_select '[role="tablist"]', 1
    assert_select '[role="tab"]', 3
    assert_select '[role="tabpanel"]', 3
    assert_select '[role="tab"]', text: /About/
    assert_select '[role="tab"]', text: /Members/
    assert_select '[role="tab"]', text: /Settings/
  end

  # Creator update permission tests

  test "creator can update their own closed channel" do
    sign_in :kevin
    post channels_closeds_url, params: { channel: { name: "Kevin's Channel" } }
    channel = Channel.last

    put channels_closed_url(channel), params: { channel: { name: "Kevin's Updated Channel" } }

    assert_redirected_to channel_url(channel)
    assert_equal "Kevin's Updated Channel", channel.reload.name
  end

  test "a direct channel can't be converted into a closed channel" do
    sign_in :kevin
    direct = Channels::Direct.create_for({ creator: users(:kevin) }, users: [ users(:kevin), users(:jz) ])

    put channels_closed_url(direct), params: { channel: { name: "Seized" } }

    assert_redirected_to root_url
    assert_equal "Channels::Direct", Channel.find(direct.id).type
  end

  test "a chat thread can't be converted into a closed channel" do
    sign_in :kevin
    message = channels(:designers).messages.create!(creator: users(:kevin), body: "private")
    thread = Channels::Thread.find_or_create_for(message, creator: users(:kevin))

    put channels_closed_url(thread), params: { channel: { name: "Seized" } }

    assert_redirected_to root_url
    assert_equal "Channels::Thread", Channel.find(thread.id).type
  end
end
