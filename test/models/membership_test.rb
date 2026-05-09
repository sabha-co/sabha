require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  setup do
    @membership = memberships(:david_watercooler)
  end

  test "connected scope" do
    @membership.connected
    assert Membership.connected.exists?(@membership.id)

    @membership.disconnected
    assert_not Membership.connected.exists?(@membership.id)

    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    assert_not Membership.connected.exists?(@membership.id)
  end

  test "disconnected scope" do
    @membership.disconnected
    assert Membership.disconnected.exists?(@membership.id)

    @membership.connected
    assert_not Membership.disconnected.exists?(@membership.id)

    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    assert Membership.disconnected.exists?(@membership.id)
  end

  test "connected? is false when connection is stale" do
    @membership.connected
    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    assert_not @membership.connected?
  end

  test "connecting" do
    @membership.connected
    assert @membership.connected?
    assert_equal 1, @membership.connections

    @membership.connected
    assert_equal 2, @membership.connections
  end

  test "connecting resets stale connection count" do
    2.times { @membership.connected }
    assert_equal 2, @membership.connections

    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    @membership.connected
    assert_equal 1, @membership.connections
  end

  test "disconnecting" do
    2.times { @membership.connected }

    @membership.disconnected
    assert @membership.connected?
    assert_equal 1, @membership.connections

    @membership.disconnected
    assert_not @membership.connected?
    assert_equal 0, @membership.connections
  end

  test "disconnecting resets stale connection count" do
    2.times { @membership.connected }
    assert_equal 2, @membership.connections

    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    @membership.disconnected
    assert_equal 0, @membership.connections
  end

  test "refreshing the connection" do
    @membership.connected

    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    assert_not @membership.connected?

    @membership.refresh_connection
    assert @membership.connected?
  end

  test "deactivating a membership resets user connections" do
    @membership.user.expects(:reset_remote_connections)
    @membership.deactivate!
  end

  test "updating a non-active field does not reset user connections" do
    @membership.user.expects(:reset_remote_connections).never
    @membership.update!(involvement: :everything)
  end

  test "removing a membership resets the user's connections" do
    @membership.user.expects :reset_remote_connections

    @membership.destroy
  end

  # Activity status tests

  test "activity_status returns :active when connected within 10 minutes" do
    assert_equal :active, Membership.activity_status(2.minutes.ago)
    assert_equal :active, Membership.activity_status(9.minutes.ago)
    assert_equal :active, Membership.activity_status(Time.current)
  end

  test "activity_status returns :away when connected within 1 hour" do
    assert_equal :away, Membership.activity_status(11.minutes.ago)
    assert_equal :away, Membership.activity_status(30.minutes.ago)
    assert_equal :away, Membership.activity_status(59.minutes.ago)
  end

  test "activity_status returns :offline when connected over 1 hour ago or never" do
    assert_equal :offline, Membership.activity_status(2.hours.ago)
    assert_equal :offline, Membership.activity_status(nil)
  end

  test "last_connected_at_for returns max connected_at per user" do
    david = users(:david)

    # Set different connected_at across david's memberships
    Membership.unscoped.where(user_id: david.id).update_all(connected_at: 1.hour.ago)
    memberships(:david_watercooler).update_column(:connected_at, 2.minutes.ago)

    result = Membership.last_connected_at_for([ david.id ])

    assert_in_delta memberships(:david_watercooler).reload.connected_at, result[david.id], 1.second
  end

  test "last_connected_at_for returns results for multiple users" do
    david = users(:david)
    jason = users(:jason)

    Membership.unscoped.where(user_id: [ david.id, jason.id ]).update_all(connected_at: 1.day.ago)
    memberships(:david_watercooler).update_column(:connected_at, 3.minutes.ago)
    memberships(:jason_watercooler).update_column(:connected_at, 30.minutes.ago)

    result = Membership.last_connected_at_for([ david.id, jason.id ])

    assert_equal :active, Membership.activity_status(result[david.id])
    assert_equal :away, Membership.activity_status(result[jason.id])
  end

  # Starred tests

  test "starred scope returns starred memberships" do
    @membership.update!(starred: true)
    assert Membership.starred.exists?(@membership.id)
    assert_not Membership.unstarred.exists?(@membership.id)
  end

  test "unstarred scope returns unstarred memberships" do
    @membership.update!(starred: false)
    assert Membership.unstarred.exists?(@membership.id)
    assert_not Membership.starred.exists?(@membership.id)
  end

  test "cannot star a direct room membership" do
    membership = memberships(:david_david_and_jason)
    membership.starred = true
    assert_not membership.valid?
    assert_includes membership.errors[:starred], "is not allowed for direct or thread rooms"
  end

  test "hiding a starred room automatically unstars it" do
    @membership.update!(starred: true)
    @membership.update!(involvement: :invisible)
    assert_not @membership.reload.starred?
  end

  # Read/Unread tests

  test "mark_unread_at sets unread_at to message created_at" do
    message = @membership.room.messages.create!(creator: users(:jason), body: "Test")
    @membership.update!(unread_at: nil)

    @membership.mark_unread_at(message)

    assert_equal message.created_at, @membership.unread_at
    assert @membership.unread?
  end

  test "read clears unread_at" do
    @membership.update!(unread_at: 1.hour.ago)

    @membership.read

    assert_nil @membership.unread_at
    assert @membership.read?
  end

  test "read? and unread? are opposites" do
    @membership.update!(unread_at: nil)
    assert @membership.read?
    assert_not @membership.unread?

    @membership.update!(unread_at: 1.hour.ago)
    assert_not @membership.read?
    assert @membership.unread?
  end

  # Leave! tests

  test "leave! makes membership invisible" do
    assert_not @membership.involved_in_invisible?
    @membership.leave!
    assert @membership.reload.involved_in_invisible?
  end

  test "leave! works for open rooms even as last member" do
    open_room = rooms(:hq)
    assert open_room.open?

    # Get the only visible membership
    membership = open_room.memberships.visible.first

    # Should not raise error
    assert_nothing_raised do
      membership.leave!
    end

    assert membership.reload.involved_in_invisible?
  end

  test "leave! raises LastVisibleMemberError for closed rooms when last visible member" do
    closed_room = rooms(:designers)
    assert closed_room.closed?

    # Make all but one membership invisible
    visible_memberships = closed_room.memberships.visible.to_a
    assert visible_memberships.count > 1

    visible_memberships[1..-1].each do |m|
      m.update!(involvement: :invisible)
    end

    # Now only one visible membership remains
    last_membership = closed_room.memberships.visible.first
    assert_equal 1, closed_room.memberships.visible.count

    assert_raises(Membership::LastVisibleMemberError) do
      last_membership.leave!
    end

    # Should still be visible
    assert_not last_membership.reload.involved_in_invisible?
  end

  test "leave! allows leaving closed room when multiple visible members exist" do
    closed_room = rooms(:designers)
    assert closed_room.closed?
    assert closed_room.memberships.visible.count > 1

    membership = closed_room.memberships.visible.first

    assert_nothing_raised do
      membership.leave!
    end

    assert membership.reload.involved_in_invisible?
  end

  # Mention-aware unread notification tests

  test "unread_notifications returns mentioned messages for non-direct rooms" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: 1.day.ago)

    # Message mentioning david — should be an unread notification
    mentioned_msg = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "unread_mention_1"
    )

    # Message NOT mentioning david — should NOT be an unread notification
    room.messages.create!(
      body: "<div>Hello general</div>",
      creator: users(:jason),
      client_message_id: "unread_general_1"
    )

    assert_includes membership.unread_notifications, mentioned_msg
    assert_equal 1, membership.unread_notifications.count
  end

  test "unread_notifications returns all messages for direct rooms" do
    dm_room = rooms(:david_and_jason)
    membership = dm_room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: 1.day.ago)

    msg = dm_room.messages.create!(
      body: "Hey!",
      creator: users(:jason),
      client_message_id: "dm_unread_1"
    )

    assert_includes membership.unread_notifications, msg
  end

  test "unread_notifications includes @everyone messages" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: 1.day.ago)

    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    msg = Message.create!(
      room: room,
      body: body_html,
      creator: users(:jason),
      client_message_id: "everyone_unread_1"
    )

    assert_includes membership.unread_notifications, msg
  end

  test "has_unread_notifications? true when mentioned in unread messages" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: 1.day.ago)

    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "has_unread_1"
    )

    assert membership.reload.has_unread_notifications?
  end

  test "has_unread_notifications? false when no mentions in unread messages" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: 1.day.ago)

    room.messages.create!(
      body: "<div>No mentions here</div>",
      creator: users(:jason),
      client_message_id: "no_unread_1"
    )

    assert_not membership.reload.has_unread_notifications?
  end

  test "has_unread_notifications? false when read" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: nil)

    assert_not membership.has_unread_notifications?
  end

  test "unread_notifications_count tracks mentioned unread messages" do
    room = rooms(:pets)
    david_membership = room.memberships.find_by(user: users(:david))
    david_membership.update!(unread_at: 1.day.ago)

    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "count_1"
    )
    room.messages.create!(
      body: "<div>Again #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "count_2"
    )

    assert_equal 2, david_membership.reload.unread_notifications_count
  end

  test "unread_notifications_count not bumped by non-mentioning messages" do
    room = rooms(:pets)
    david_membership = room.memberships.find_by(user: users(:david))
    david_membership.update!(unread_at: 1.day.ago)

    room.messages.create!(
      body: "<div>No mention</div>",
      creator: users(:jason),
      client_message_id: "count_none"
    )

    assert_equal 0, david_membership.reload.unread_notifications_count
  end

  test "unread_notifications_count zero when read" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: nil)

    assert_equal 0, membership.unread_notifications_count
  end

  test "unread_notifications_count drops when a mention message is soft-deleted" do
    room = rooms(:pets)
    david_membership = room.memberships.find_by(user: users(:david))
    david_membership.update!(unread_at: 1.day.ago)

    message = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "decrement_mention_1"
    )

    assert_equal 1, david_membership.reload.unread_notifications_count

    message.deactivate

    assert_equal 0, david_membership.reload.unread_notifications_count
  end

  test "unread_notifications_count drops when a DM message is soft-deleted" do
    dm_room = rooms(:david_and_jason)
    membership = dm_room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: 1.day.ago)

    earlier = dm_room.messages.create!(
      body: "first",
      creator: users(:jason),
      client_message_id: "dm_decrement_1"
    )
    later = dm_room.messages.create!(
      body: "second",
      creator: users(:jason),
      client_message_id: "dm_decrement_2"
    )

    assert_equal 2, membership.reload.unread_notifications_count

    later.deactivate

    assert_equal 1, membership.reload.unread_notifications_count

    earlier.deactivate

    assert_equal 0, membership.reload.unread_notifications_count
  end

  test "unread_notifications_count drops when a mention message is hard-destroyed" do
    room = rooms(:pets)
    david_membership = room.memberships.find_by(user: users(:david))
    david_membership.update!(unread_at: 1.day.ago)

    message = room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      creator: users(:jason),
      client_message_id: "destroy_mention_1"
    )

    assert_equal 1, david_membership.reload.unread_notifications_count

    message.destroy!

    assert_equal 0, david_membership.reload.unread_notifications_count
  end

  test "unread_notifications_count drops when a DM message is hard-destroyed" do
    dm_room = rooms(:david_and_jason)
    membership = dm_room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: 1.day.ago)

    earlier = dm_room.messages.create!(
      body: "first",
      creator: users(:jason),
      client_message_id: "dm_destroy_1"
    )
    later = dm_room.messages.create!(
      body: "second",
      creator: users(:jason),
      client_message_id: "dm_destroy_2"
    )

    assert_equal 2, membership.reload.unread_notifications_count

    later.destroy!
    assert_equal 1, membership.reload.unread_notifications_count

    earlier.destroy!
    assert_equal 0, membership.reload.unread_notifications_count
  end

  test "unread_notifications_count restores when a soft-deleted DM message is reactivated" do
    dm_room = rooms(:david_and_jason)
    membership = dm_room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: 1.day.ago)

    message = dm_room.messages.create!(
      body: "hello",
      creator: users(:jason),
      client_message_id: "dm_reactivate_1"
    )

    assert_equal 1, membership.reload.unread_notifications_count

    message.deactivate
    assert_equal 0, membership.reload.unread_notifications_count

    message.activate
    assert_equal 1, membership.reload.unread_notifications_count
  end

  test "unread_notifications_count restores when a soft-deleted @everyone message is reactivated" do
    room = rooms(:pets)
    membership = room.memberships.find_by(user: users(:david))
    membership.update!(unread_at: 1.day.ago)

    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"
    message = Message.create!(
      room: room,
      body: body_html,
      creator: users(:jason),
      client_message_id: "everyone_reactivate_1"
    )

    assert_equal 1, membership.reload.unread_notifications_count

    message.deactivate
    assert_equal 0, membership.reload.unread_notifications_count

    message.activate
    assert_equal 1, membership.reload.unread_notifications_count
  end

  test "unread_notifications_count bumps the DM sender when their unread window includes the message" do
    dm_room = rooms(:david_and_jason)
    sender_membership = dm_room.memberships.find_by(user: users(:jason))
    sender_membership.update!(unread_at: 1.day.ago)

    dm_room.messages.create!(
      body: "self-aware",
      creator: users(:jason),
      client_message_id: "dm_sender_in_window"
    )

    assert_equal 1, sender_membership.reload.unread_notifications_count
  end

  test "unread_notifications_count recomputes when DM message at the unread anchor is soft-deleted" do
    dm_room = rooms(:david_and_jason)
    membership = dm_room.memberships.find_by(user: users(:david))

    anchor = dm_room.messages.create!(
      body: "anchor",
      creator: users(:jason),
      client_message_id: "dm_anchor"
    )
    follow_up = dm_room.messages.create!(
      body: "follow up",
      creator: users(:jason),
      client_message_id: "dm_follow_up"
    )

    membership.update!(unread_at: anchor.created_at, unread_notifications_count: 2)

    anchor.deactivate

    membership.reload
    assert_equal follow_up.created_at, membership.unread_at
    assert_equal 1, membership.unread_notifications_count
  end

  test "receives_mentions? true for mentions and everything involvement" do
    membership = memberships(:david_pets)

    membership.update!(involvement: :mentions)
    assert membership.receives_mentions?

    membership.update!(involvement: :everything)
    assert membership.receives_mentions?
  end

  test "receives_mentions? false for nothing and invisible involvement" do
    membership = memberships(:david_pets)

    membership.update!(involvement: :nothing)
    assert_not membership.receives_mentions?

    membership.update!(involvement: :invisible)
    assert_not membership.receives_mentions?
  end

  test "ensure_receives_mentions! upgrades involvement to mentions" do
    membership = memberships(:david_pets)
    membership.update!(involvement: :nothing)

    membership.ensure_receives_mentions!

    assert_equal "mentions", membership.reload.involvement
  end

  test "ensure_receives_mentions! does not downgrade everything to mentions" do
    membership = memberships(:david_pets)
    membership.update!(involvement: :everything)

    membership.ensure_receives_mentions!

    assert_equal "everything", membership.reload.involvement
  end

  # ---------- effective_involvement ----------

  test "effective_involvement returns :everything for per-room everything" do
    membership = memberships(:david_watercooler)
    membership.update!(involvement: :everything)

    assert_equal :everything, membership.effective_involvement
  end

  test "effective_involvement returns :mentions for per-room mentions when no settings exist" do
    membership = memberships(:kevin_designers)
    membership.update!(involvement: :mentions)

    assert_nil membership.user.try(:notification_settings),
      "U2 has not landed yet — settings association should not exist"
    assert_equal :mentions, membership.effective_involvement
  end

  test "effective_involvement returns :nothing for per-room nothing when no settings exist" do
    membership = memberships(:kevin_designers)
    membership.update!(involvement: :nothing)

    assert_equal :nothing, membership.effective_involvement
  end

  test "effective_involvement returns :invisible for per-room invisible" do
    membership = memberships(:kevin_designers)
    membership.update!(involvement: :invisible)

    assert_equal :invisible, membership.effective_involvement
  end

  test "effective_involvement falls back to per-room value when notification_settings is missing (rule 3)" do
    # U1 ships before U2 lands the User::NotificationSettings model. Until then
    # `user.try(:notification_settings)` returns nil, the global mode rule cannot
    # fire, and the predicate must default to the per-room involvement value.
    membership = memberships(:kevin_designers)
    membership.update!(involvement: :mentions)

    assert_equal :mentions, membership.effective_involvement
  end
end
