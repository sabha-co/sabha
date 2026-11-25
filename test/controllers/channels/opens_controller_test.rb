require "test_helper"

class Channels::OpensControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show redirects to get general show" do
    get channels_open_url(users(:david).channels.opens.last)
    assert_redirected_to channel_url(users(:david).channels.opens.last)
  end

  test "new renders the unified channel form posting to channels_opens" do
    get new_channels_open_url

    assert_response :success
    assert_select "form[action=?]", channels_opens_path
    assert_select "input[name='channel[name]']"
  end

  test "create without auto_join redirects to channel" do
    # 1 per-user broadcast to shared_channels (new channels are never starred)
    assert_turbo_stream_broadcasts [ users(:david), :channels ], count: 1 do
      post channels_opens_url, params: { channel: { name: "My New Channel" } }
    end

    assert_equal 1, Channel.last.memberships.count
    assert_redirected_to channel_url(Channel.last)
  end

  test "create with auto_join adds all users and redirects to channel" do
    post channels_opens_url, params: { channel: { name: "Forced Channel", auto_join: true } }

    assert_equal User.count, Channel.last.memberships.count
    assert Channel.last.auto_join?
    assert_redirected_to channel_url(Channel.last)
  end

  test "create with auto_join persists flag so future users are auto-joined" do
    post channels_opens_url, params: { channel: { name: "Persistent Auto Channel", auto_join: true } }
    channel = Channel.last

    new_user = User.create!(name: "Future User", email_address: "future@example.com", password: "secret123456")

    assert channel.auto_join?, "Channel should persist auto_join flag"
    assert channel.memberships.exists?(user: new_user), "Future user should be auto-joined"
  end

  test "only admins or creators can update" do
    sign_in :jz

    assert_turbo_stream_broadcasts [ accounts(:signal), :channels ], count: 0 do
      put channels_open_url(channels(:hq)), params: { channel: { name: "New Name" } }
    end

    assert_response :forbidden
    assert_equal "HQ", channels(:hq).reload.name, "name must not change on forbidden update"
  end

  test "update" do
    # Broadcasts happen via ChannelUpdateBroadcastJob which is async
    put channels_open_url(channels(:pets)), params: { channel: { name: "New Name" } }

    assert_redirected_to channel_url(channels(:pets))
    assert_equal "New Name", channels(:pets).reload.name
  end

  test "update a closed channel to be open does not auto-add all users" do
    original_count = channels(:designers).memberships.count
    put channels_open_url(channels(:designers)), params: { channel: { name: "Doesn't matter" } }
    assert_equal original_count, channels(:designers).memberships.count
  end

  test "update a closed channel to be open with auto_join adds all users" do
    put channels_open_url(channels(:designers)), params: { channel: { name: "Doesn't matter", auto_join: true } }
    assert_equal User.count, channels(:designers).memberships.count
  end

  test "non-admin cannot create channel when restricted to administrators" do
    accounts(:signal).settings.restrict_channel_creation_to_administrators = true
    accounts(:signal).save!

    sign_in :jz  # non-admin user

    get new_channels_open_url
    assert_response :forbidden

    post channels_opens_url, params: { channel: { name: "My New Channel" } }
    assert_response :forbidden
  end

  test "admin can create channel when restricted to administrators" do
    accounts(:signal).settings.restrict_channel_creation_to_administrators = true
    accounts(:signal).save!

    sign_in :david  # admin user

    get new_channels_open_url
    assert_response :success

    post channels_opens_url, params: { channel: { name: "Admin Channel" } }
    assert_redirected_to channel_url(Channel.last)
  end

  # Destroy permission tests

  test "admin can destroy any channel" do
    sign_in :david

    assert_difference -> { Channel.active.count }, -1 do
      delete channels_open_url(channels(:pets))
    end

    assert_redirected_to root_url
  end

  test "creator can destroy their own channel" do
    # Create a channel as non-admin
    sign_in :kevin
    post channels_opens_url, params: { channel: { name: "Kevin's Channel" } }
    channel = Channel.last

    assert_difference -> { Channel.active.count }, -1 do
      delete channels_open_url(channel)
    end

    assert_redirected_to root_url
  end

  test "non-admin non-creator cannot destroy channel" do
    sign_in :kevin

    assert_no_difference -> { Channel.active.count } do
      delete channels_open_url(channels(:hq))
    end

    assert_response :forbidden
  end

  test "non-member cannot access channel" do
    # Create a closed channel without kevin
    sign_in :david
    post channels_closeds_url, params: { channel: { name: "Private Channel" }, user_ids: [ users(:david).id ] }
    channel = Channel.last

    sign_in :kevin

    get channel_url(channel)
    assert_redirected_to root_url
  end

  # Event messages

  test "update posts rename event when name changes" do
    channel = channels(:pets)

    assert_difference -> { Message.unscoped.where(channel: channel, event: "channel_renamed").count } do
      put channels_open_url(channel), params: { channel: { name: "New Pets Name" } }
    end

    event = Message.unscoped.where(channel: channel, event: "channel_renamed").last
    assert_equal "renamed the channel from All Pets to New Pets Name", event.reload.plain_text_body
  end

  test "update does not post rename event when name unchanged" do
    channel = channels(:pets)

    assert_no_difference -> { Message.unscoped.where(channel: channel, event: "channel_renamed").count } do
      put channels_open_url(channel), params: { channel: { name: channel.name } }
    end
  end

  # Tabbed edit layout

  test "edit renders tabbed layout with three tabs" do
    get edit_channels_open_url(channels(:pets))
    assert_response :success
    assert_select '[role="tablist"]', 1
    assert_select '[role="tab"]', 3
    assert_select '[role="tabpanel"]', 3
    assert_select '[role="tab"]', text: /About/
    assert_select '[role="tab"]', text: /Members/
    assert_select '[role="tab"]', text: /Settings/
  end

  # Creator update permission tests

  test "creator can update their own open channel" do
    sign_in :kevin
    post channels_opens_url, params: { channel: { name: "Kevin's Channel" } }
    channel = Channel.last

    put channels_open_url(channel), params: { channel: { name: "Kevin's Updated Channel" } }

    assert_redirected_to channel_url(channel)
    assert_equal "Kevin's Updated Channel", channel.reload.name
  end

  # Only open and closed channels are in reach here. Every case below is a channel its
  # creator administers, so the permission check passes and the channel type is the
  # only thing standing between a private conversation and the whole account.

  test "a direct channel can't be promoted to an open channel by a participant" do
    sign_in :kevin
    direct = Channels::Direct.create_for({ creator: users(:kevin) }, users: [ users(:kevin), users(:jz) ])

    put channels_open_url(direct), params: { channel: { name: "Leaked" } }

    assert_redirected_to root_url
    assert_equal "Channels::Direct", Channel.find(direct.id).type
    assert_not Channel.browsable_by(users(:rachel)).exists?(id: direct.id)
  end

  test "a direct channel can't be promoted to an open channel by an administrator" do
    put channels_open_url(channels(:david_and_kevin)), params: { channel: { name: "Leaked" } }

    assert_redirected_to root_url
    assert_equal "Channels::Direct", Channel.find(channels(:david_and_kevin).id).type
  end

  test "a chat thread can't be promoted out of its closed channel into an open one" do
    sign_in :kevin
    message = channels(:designers).messages.create!(creator: users(:kevin), body: "private")
    thread = Channels::Thread.find_or_create_for(message, creator: users(:kevin))

    put channels_open_url(thread), params: { channel: { name: "Leaked" } }

    assert_redirected_to root_url
    assert_equal "Channels::Thread", Channel.find(thread.id).type
    assert_not Channel.browsable_by(users(:rachel)).exists?(id: thread.id)
  end

  test "a forum can't be converted into an open channel" do
    put channels_open_url(channels(:help_desk)), params: { channel: { name: "Leaked" } }

    assert_redirected_to root_url
    assert_equal "Channels::Forum", Channel.find(channels(:help_desk).id).type
  end
end
