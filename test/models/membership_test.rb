require "test_helper"
require "rails/dom/testing/assertions"

class MembershipTest < ActiveSupport::TestCase
  include ActionCable::TestHelper, Rails::Dom::Testing::Assertions::SelectorAssertions

  setup do
    @membership = memberships(:david_watercooler)
  end

  # Membership.connect writes with update_all, so the in-memory record doesn't
  # see its own write. Reload every time rather than leave that to each test.
  def present(membership)
    membership.present
    membership.reload
  end

  # Counts statements that take the SQLite writer. A SELECT is free; an UPDATE
  # is the thing this work exists to remove.
  def writes_while
    writes = 0
    counter = ->(_name, _start, _finish, _id, payload) do
      writes += 1 if payload[:sql] =~ /\A\s*(INSERT|UPDATE|DELETE)/i
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    writes
  end

  test "connected scope" do
    present @membership
    assert Membership.connected.exists?(@membership.id)

    @membership.disconnect
    assert_not Membership.connected.exists?(@membership.id)

    present @membership
    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    assert_not Membership.connected.exists?(@membership.id)
  end

  test "disconnected scope is the exact negation of connected" do
    present @membership
    assert_not Membership.disconnected.exists?(@membership.id)

    @membership.disconnect
    assert Membership.disconnected.exists?(@membership.id)

    assert_equal Membership.count, Membership.connected.count + Membership.disconnected.count,
      "every membership is one or the other — no row may fall between the two scopes"
  end

  test "connected? needs a live connection AND fresh last-seen" do
    present @membership
    assert @membership.connected?

    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    assert_not @membership.connected?, "stale last-seen: the socket died without saying so"

    @membership.update_columns(connected_at: Time.current, connections: 0)
    assert_not @membership.connected?, "no connections: they left, however fresh last-seen looks"
  end

  test "presenting counts each tab" do
    present @membership
    assert_equal 1, @membership.connections

    present @membership
    assert_equal 2, @membership.connections
  end

  test "presenting resets stale connection count" do
    2.times { present @membership }
    assert_equal 2, @membership.connections

    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    present @membership
    assert_equal 1, @membership.connections
  end

  test "disconnecting" do
    2.times { present @membership }

    @membership.disconnect
    assert @membership.reload.connected?
    assert_equal 1, @membership.connections

    @membership.disconnect
    assert_not @membership.reload.connected?
    assert_equal 0, @membership.connections
  end

  test "disconnecting resets stale connection count" do
    2.times { present @membership }
    assert_equal 2, @membership.connections

    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    @membership.disconnect
    assert_equal 0, @membership.reload.connections
  end

  test "fully disconnecting keeps last-seen, so email measures from real activity" do
    Membership.unscoped.where(user_id: @membership.user_id).update_all(connected_at: nil, connections: 0)
    present @membership

    @membership.disconnect

    assert_not_nil @membership.reload.connected_at,
      "wiping last-seen on disconnect is what made a member look instantly away"
    assert_not Membership.workspace_locally_away?(@membership.user_id), "just left is not away"

    travel_to Membership::Connectable::ACTIVITY_TIERS[:away].from_now + 1.minute
    assert Membership.workspace_locally_away?(@membership.user_id)
  end

  # The heartbeat used to write two rows every 50s per open tab, whatever
  # was happening — the largest concurrency-scaled load on a single SQLite
  # writer. These pin that idle watching now writes nothing at all.
  test "a heartbeat with fresh last-seen writes nothing" do
    present @membership

    assert_equal 0, writes_while { @membership.reload.refresh_connection },
      "an idle watcher must cost zero writes — this is the whole point of the exercise"
  end

  test "a heartbeat past the write threshold writes exactly once" do
    present @membership
    travel_to Membership::Connectable::CONNECTION_REFRESH_THRESHOLD.from_now + 1

    assert_equal 1, writes_while { @membership.reload.refresh_connection },
      "last-seen and the read cursor ride one UPDATE — two would take the writer twice per watcher"
  end

  test "a heartbeat past the threshold carries the read cursor with it" do
    present @membership
    message = @membership.room.messages.create! \
      body: "seen live", creator: users(:jason), client_message_id: "heartbeat_cursor"

    travel_to Membership::Connectable::CONNECTION_REFRESH_THRESHOLD.from_now + 1
    @membership.reload.refresh_connection

    assert_equal message.id, @membership.reload.last_read_message_id
  end

  test "a heartbeat never advances the cursor past an explicit mark-as-unread" do
    present @membership
    message = @membership.room.messages.create! \
      body: "marked", creator: users(:jason), client_message_id: "heartbeat_marked"
    @membership.reload.mark_unread_at(message)

    travel_to Membership::Connectable::CONNECTION_REFRESH_THRESHOLD.from_now + 1
    @membership.reload.refresh_connection

    assert @membership.reload.unread?, "an explicit mark must survive the heartbeat"
    assert_equal message, @membership.first_unread_message
    assert_operator @membership.connected_at, :>, 1.minute.ago, "…while last-seen still refreshes"
  end

  test "the timing constants stay in the order the design depends on" do
    client_cadence = 2.minutes # presence_controller.js REFRESH_INTERVAL

    assert_operator client_cadence, :<, Membership::Connectable::CONNECTION_REFRESH_THRESHOLD,
      "a watcher must beat more often than the server writes, or every beat writes"
    assert_operator Membership::Connectable::CONNECTION_REFRESH_THRESHOLD, :<, Membership::Connectable::CONNECTION_TTL,
      "last-seen must be rewritten before it goes stale, or watchers flicker offline between their own beats"
    assert_operator Membership::Connectable::CONNECTION_TTL, :<, Membership::Connectable::ACTIVITY_TIERS[:active],
      "a member must read as disconnected before their dot stops saying active"
  end

  # The unread scopes ask "were they watching when this landed?" in SQL. They
  # used to answer with last-seen freshness alone, which was fine while a
  # disconnect wiped the timestamp. Now that it survives (so email can measure
  # from real activity) freshness alone would call a member who left an hour's
  # worth of messages ago "still watching" for a full TTL.
  test "a departed member with fresh last-seen still shows unread by scope" do
    present @membership
    @membership.disconnect # cursor to head, refcount to zero, last-seen kept

    @membership.room.messages.create! \
      body: "arrived after they left", creator: users(:jason), client_message_id: "after_depart"

    assert Membership.unread.exists?(@membership.id),
      "fresh last-seen must not mask a member who actually left — that is what the refcount is for"
    assert_not Membership.read.exists?(@membership.id)
    assert @membership.reload.unread?
  end

  test "a watching member's room never flips unread" do
    present @membership

    @membership.room.messages.create! \
      body: "arrived while watching", creator: users(:jason), client_message_id: "while_watching"

    assert Membership.read.exists?(@membership.id)
    assert_not Membership.unread.exists?(@membership.id), "a member watching a room must never see it flip unread"
    assert @membership.reload.read?
  end

  test "with_message_unseen skips a watcher but catches a member who has left" do
    present @membership
    message = @membership.room.messages.create! \
      body: "landed", creator: users(:jason), client_message_id: "unseen_scope"
    @membership.reload.update_columns(last_read_at: 1.hour.ago, last_read_message_id: 0)

    assert_empty Membership.with_message_unseen(message.created_at, message.id).where(id: @membership.id),
      "a watching member saw it land"

    @membership.update_columns(connections: 0) # left; last-seen still fresh

    assert_not_empty Membership.with_message_unseen(message.created_at, message.id).where(id: @membership.id),
      "a departed member did not"
  end

  test "a refresh landing after depart does not resurrect a departed membership" do
    present @membership
    @membership.disconnect
    assert_equal 0, @membership.reload.connections

    @membership.refresh_connection

    assert_equal 0, @membership.reload.connections
    assert_not @membership.connected?
  end

  # A broker restart fires no depart, so the dead session's +1 is never
  # given back and the next present ratchets the count. The over-count is
  # accepted rather than prevented — every way of preventing it costs an HTTP
  # call on the connection-establishment path, which is the measured ceiling.
  # These two pin why accepting it is safe.
  test "a ratcheted refcount still counts watched messages as seen when the member leaves" do
    present @membership
    present @membership # broker restart: no depart fired, so this ratchets
    assert_equal 2, @membership.connections, "the ratchet is accepted, not prevented"

    watched = @membership.room.messages.create! \
      body: "watched live", creator: users(:jason), client_message_id: "ratchet"

    @membership.disconnect

    assert_equal 1, @membership.reload.connections, "still over-counted…"
    assert_equal watched.id, @membership.last_read_message_id,
      "…but the cursor advances anyway: the advance must not wait for the refcount to reach zero"
  end

  test "an over-counted refcount reads as connected only until last-seen goes stale" do
    present @membership
    present @membership
    @membership.disconnect

    assert @membership.reload.connected?,
      "the accepted harm: reads connected though the member left — same shape as a silent transport death"

    travel_to Membership::Connectable::CONNECTION_TTL.from_now + 1
    assert_not @membership.connected?, "and it heals on the TTL that already bounds a silent death"

    present @membership
    assert_equal 1, @membership.connections, "the next present clears the drift entirely"
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
    assert_equal :active, Membership.activity_status(2.minutes.ago, connected: true)
    assert_equal :active, Membership.activity_status(9.minutes.ago, connected: true)
    assert_equal :active, Membership.activity_status(Time.current, connected: true)
  end

  test "activity_status returns :away when connected within 1 hour" do
    assert_equal :away, Membership.activity_status(11.minutes.ago, connected: true)
    assert_equal :away, Membership.activity_status(30.minutes.ago, connected: true)
    assert_equal :away, Membership.activity_status(59.minutes.ago, connected: true)
  end

  test "activity_status returns :offline when connected over 1 hour ago or never" do
    assert_equal :offline, Membership.activity_status(2.hours.ago, connected: true)
    assert_equal :offline, Membership.activity_status(nil, connected: true)
  end

  # Preserving last-seen for email must not leave a green dot burning for
  # ten minutes after someone closes their browser. The dot's "are they here"
  # half reads the refcount; only its "how long ago" half reads last-seen.
  test "activity_status is offline for a departed member however fresh last-seen is" do
    assert_equal :active, Membership.activity_status(2.minutes.ago, connected: true)
    assert_equal :offline, Membership.activity_status(2.minutes.ago, connected: false)
  end

  test "activity_statuses_for greys a departed member at once while last-seen survives" do
    david = users(:david)
    Membership.unscoped.where(user_id: david.id).update_all(connected_at: nil, connections: 0)

    present @membership
    assert_equal :active, Membership.activity_statuses_for([ david.id ])[david.id]

    @membership.disconnect

    assert_equal :offline, Membership.activity_statuses_for([ david.id ])[david.id],
      "closing the browser greys the dot immediately, exactly as it did before last-seen was preserved"
    assert_not_nil @membership.reload.connected_at, "…and last-seen still survives, for email"
  end

  # online? and online_user_count answer a different question than the dot —
  # "how many people have been around lately" — so they stay last-seen-based.
  # They must agree with each other, though: accounts_helper adds one to the
  # count when online? is false, and would double-count otherwise.
  test "online? stays last-seen based, so a member who just left still counts as around" do
    david = users(:david)
    Membership.unscoped.where(user_id: david.id).update_all(connected_at: nil, connections: 0)

    present @membership
    @membership.disconnect

    assert Membership.online?(david), "they were here a moment ago"
    assert_empty Membership.connected.where(user_id: david.id), "…though they hold no connection"
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

    assert_equal :active, Membership.activity_status(result[david.id], connected: true)
    assert_equal :away, Membership.activity_status(result[jason.id], connected: true)
  end

  test "online? is true only when the user has a membership connected within the active tier" do
    david = users(:david)
    Membership.unscoped.where(user_id: david.id).update_all(connected_at: nil)

    refute Membership.online?(david)

    memberships(:david_watercooler).update_column(:connected_at, 1.minute.ago)
    assert Membership.online?(david)

    memberships(:david_watercooler).update_column(:connected_at, 30.minutes.ago)
    refute Membership.online?(david)
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

  test "mark_unread_at makes the message the first unread" do
    message = @membership.room.messages.create!(creator: users(:jason), body: "Test")
    catch_up @membership

    @membership.mark_unread_at(message)

    assert @membership.unread?
    assert_equal message, @membership.first_unread_message
  end

  test "read clears unread state" do
    message = @membership.room.messages.create!(creator: users(:jason), body: "Unseen")
    rewind_unread_to @membership, message

    @membership.read

    assert @membership.read?
    assert_nil @membership.first_unread_message
  end

  test "read? and unread? are opposites" do
    message = @membership.room.messages.create!(creator: users(:jason), body: "Unseen")

    catch_up @membership
    assert @membership.read?
    assert_not @membership.unread?

    rewind_unread_to @membership, message
    assert_not @membership.read?
    assert @membership.unread?
  end

  test "a membership with no cursor yet reads as read, not all-unread" do
    @membership.room.messages.create!(creator: users(:jason), body: "History")
    @membership.update_columns(last_read_at: nil, last_read_message_id: nil, marked_unread: false)

    assert @membership.read?
    assert_not Membership.unread.exists?(@membership.id)
  end

  test "presenting in a room clears unread state and the notification badge" do
    message = @membership.room.messages.create!(creator: users(:jason), body: "Unseen")
    rewind_unread_to @membership, message
    @membership.update!(unread_notifications_count: 3)

    @membership.present

    @membership.reload
    assert @membership.read?
    assert_equal 0, @membership.unread_notifications_count
    assert @membership.connected?
  end

  test "read_until advances the anchor past the given time and recomputes the badge" do
    room = @membership.room
    first = room.messages.create!(creator: users(:jason), body: "First", client_message_id: "read_until_1")
    second = room.messages.create!(creator: users(:jason), body: "Second", client_message_id: "read_until_2")
    mention = room.messages.create!(
      creator: users(:jason),
      body: "<div>Hey #{mention_attachment_for(:david)}</div>",
      client_message_id: "read_until_3"
    )
    rewind_unread_to @membership, first

    @membership.read_until(first.created_at)

    @membership.reload
    assert @membership.unread?
    assert_equal second, @membership.first_unread_message
    assert_equal 1, @membership.unread_notifications_count, "the mention after the new anchor must still count"
    assert mention.created_at > @membership.first_unread_message.created_at
  end

  test "read_until marks read when no messages remain after the given time" do
    room = @membership.room
    last = room.messages.create!(creator: users(:jason), body: "Last", client_message_id: "read_until_last")
    rewind_unread_to @membership, last
    @membership.update!(unread_notifications_count: 2)

    @membership.read_until(last.created_at)

    @membership.reload
    assert @membership.read?
    assert_equal 0, @membership.unread_notifications_count
  end

  test "read_until ignores a time before the current anchor" do
    room = @membership.room
    first = room.messages.create!(creator: users(:jason), body: "First", client_message_id: "read_until_noop_1")
    second = room.messages.create!(creator: users(:jason), body: "Second", client_message_id: "read_until_noop_2")
    rewind_unread_to @membership, second

    @membership.read_until(first.created_at)

    assert_equal second, @membership.reload.first_unread_message
  end

  test "read_until is a no-op when already read" do
    catch_up @membership

    @membership.read_until(Time.current)

    assert @membership.reload.read?
  end

  test "fully disconnecting counts messages watched live as seen" do
    @membership.present
    @membership.room.messages.create!(creator: users(:jason), body: "Watched live", client_message_id: "watched_live")

    @membership.disconnect

    assert @membership.reload.read?, "messages that landed while connected must not dot the room after leaving"
  end

  test "disconnecting preserves an explicit mark-as-unread" do
    @membership.present
    message = @membership.room.messages.create!(creator: users(:jason), body: "Keep me unread", client_message_id: "keep_unread")
    @membership.mark_unread_at(message)

    @membership.disconnect

    @membership.reload
    assert @membership.unread?, "an explicit mark must survive leaving the room"
    assert_equal message, @membership.first_unread_message
  end

  test "refreshing the connection advances the cursor" do
    present @membership
    @membership.room.messages.create!(creator: users(:jason), body: "Seen on heartbeat", client_message_id: "heartbeat_seen")

    travel_to Membership::Connectable::CONNECTION_REFRESH_THRESHOLD.from_now + 1
    @membership.refresh_connection
    @membership.update_columns(connected_at: nil, connections: 0)

    assert @membership.reload.read?
  end

  # disconnect_all existed to reset connections "when deploying new
  # versions", from when Rails held the sockets. It doesn't any more — they
  # terminate at the anycable-go accessory and survive a web deploy — so a
  # booting release was wiping the state of members who never left, with no
  # client event to repair it. It also ran in puma's before_fork, i.e. at boot,
  # not at shutdown, so it never did the job its name implied.
  test "booting a release no longer mass-resets connected members" do
    assert_not Membership.respond_to?(:disconnect_all),
      "disconnect_all is gone: it was also the only thing resetting a drifted refcount, so removing it and tolerating that drift are one decision"

    assert_not_includes File.read(Rails.root.join("config/puma.rb")), "disconnect_all",
      "a booting web process must not wipe members whose sockets are still live on the anycable-go accessory"
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
    force_all_unread membership

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
    force_all_unread membership

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
    force_all_unread membership

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
    force_all_unread membership

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
    force_all_unread membership

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
    catch_up membership

    assert_not membership.has_unread_notifications?
  end

  test "unread_notifications_count tracks mentioned unread messages" do
    room = rooms(:pets)
    david_membership = room.memberships.find_by(user: users(:david))
    force_all_unread david_membership

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
    force_all_unread david_membership

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
    catch_up membership

    assert_equal 0, membership.unread_notifications_count
  end

  test "unread_notifications_count drops when a mention message is soft-deleted" do
    room = rooms(:pets)
    david_membership = room.memberships.find_by(user: users(:david))
    force_all_unread david_membership

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
    force_all_unread membership

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
    force_all_unread david_membership

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
    force_all_unread membership

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
    force_all_unread membership

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
    force_all_unread membership

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

    unseen = dm_room.messages.create!(
      body: "waiting for jason",
      creator: users(:david),
      client_message_id: "dm_sender_window_anchor"
    )
    rewind_unread_to sender_membership, unseen
    sender_membership.update!(unread_notifications_count: 1)

    dm_room.messages.create!(
      body: "self-aware",
      creator: users(:jason),
      client_message_id: "dm_sender_in_window"
    )

    assert_equal 2, sender_membership.reload.unread_notifications_count,
      "a sender with an open unread window keeps it, and their own DM message counts inside it"
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

    rewind_unread_to membership, anchor
    membership.update!(unread_notifications_count: 2)

    anchor.deactivate

    membership.reload
    assert_equal follow_up, membership.first_unread_message
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

  test "ensure_receives_mentions! upgrades an uninvolved invisible member to mentions" do
    membership = memberships(:david_pets)
    membership.update!(involvement: :invisible)

    membership.ensure_receives_mentions!

    assert_equal "mentions", membership.reload.involvement
  end

  test "ensure_receives_mentions! preserves an explicit nothing mute" do
    membership = memberships(:david_pets)
    membership.update!(involvement: :nothing)

    membership.ensure_receives_mentions!

    assert_equal "nothing", membership.reload.involvement,
      "posting must not silently un-mute an explicit mute"
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
      "notification settings haven't landed yet — the association should not exist"
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
    membership = memberships(:kevin_designers)
    membership.update!(involvement: :mentions)
    membership.user.notification_settings&.destroy

    assert_nil membership.user.reload.notification_settings
    assert_equal :mentions, membership.effective_involvement
  end

  test "effective_involvement returns :everything when per-room is :everything even if global mode is :nothing (rule 1 — per-room beats global mute)" do
    membership = memberships(:kevin_designers)
    membership.update!(involvement: :everything)
    membership.user.notification_settings&.update!(mode: :nothing) ||
      membership.user.create_notification_settings!(mode: :nothing)

    assert_equal :everything, membership.effective_involvement
  end

  test "effective_involvement returns :nothing when global mode is :nothing and per-room is :mentions (rule 2 — global mute applies)" do
    membership = memberships(:kevin_designers)
    membership.update!(involvement: :mentions)
    membership.user.notification_settings&.update!(mode: :nothing) ||
      membership.user.create_notification_settings!(mode: :nothing)

    assert_equal :nothing, membership.effective_involvement
  end

  # The tests below pin observable Membership callback behavior: room member-count
  # cache invalidation on save (including room_id moves), involvement broadcasts on
  # UserInvolvementsChannel, and starred broadcasts to the user's room list — plus
  # the guards that suppress star broadcasts for direct rooms and invisible
  # memberships. They assert what the callbacks emit, not how they're wired, so
  # they survive moves between the model and concerns.

  test "saving a membership invalidates the room's active_member_count cache" do
    room = @membership.room
    cache_key = room.send(:active_member_count_cache_key)

    Rails.cache.stubs(:delete)  # let unrelated cache deletes pass through
    Rails.cache.expects(:delete).with(cache_key).at_least_once
    @membership.update!(involvement: :mentions)
  end

  test "moving a membership to a new room invalidates both rooms' caches" do
    # Use rachel — only in watercooler, not in pets — to avoid UNIQUE collision.
    membership = memberships(:rachel_watercooler)
    old_room = membership.room
    new_room = rooms(:pets)
    assert_not_equal old_room.id, new_room.id

    old_key = old_room.send(:active_member_count_cache_key)
    new_key = new_room.send(:active_member_count_cache_key)

    Rails.cache.stubs(:delete)  # let unrelated cache deletes pass through
    Rails.cache.expects(:delete).with(new_key).at_least_once
    Rails.cache.expects(:delete).with(old_key).at_least_once

    membership.update!(room: new_room)
  end

  test "changing involvement broadcasts to UserInvolvementsChannel" do
    # fixture starts as :everything — move to a different value so the change fires
    ActionCable.server.pubsub.clear

    assert_broadcasts(UserInvolvementsChannel.broadcasting_for(@membership.user), 1) do
      @membership.update!(involvement: :mentions)
    end
  end

  test "non-involvement updates do not broadcast to UserInvolvementsChannel" do
    ActionCable.server.pubsub.clear

    assert_no_broadcasts(UserInvolvementsChannel.broadcasting_for(@membership.user)) do
      @membership.update!(connected_at: Time.current)
    end
  end

  test "starring a shared-room membership broadcasts remove from shared list and append to starred list" do
    # fixture starts starred: true — reset to false without firing callbacks so
    # the test's update! is the only star transition.
    @membership.update_columns(starred: false)
    ActionCable.server.pubsub.clear

    @membership.update!(starred: true)

    assert_rendered_turbo_stream_broadcast @membership.user, :rooms,
      action: "remove", target: [ @membership.room, "shared_rooms_list_node" ]
    assert_rendered_turbo_stream_broadcast @membership.user, :rooms,
      action: "append", target: :starred_rooms
  end

  test "unstarring a shared-room membership broadcasts remove from starred list and append to shared list" do
    @membership.update_columns(starred: true)  # ensure starting state
    ActionCable.server.pubsub.clear

    @membership.update!(starred: false)

    assert_rendered_turbo_stream_broadcast @membership.user, :rooms,
      action: "remove", target: [ @membership.room, "starred_rooms_list_node" ]
    assert_rendered_turbo_stream_broadcast @membership.user, :rooms,
      action: "append", target: :shared_rooms
  end

  test "non-star updates do not broadcast a star change" do
    ActionCable.server.pubsub.clear

    @membership.update!(connected_at: Time.current)

    stream_name = "#{@membership.user.to_gid_param}:rooms"
    assert_empty ActionCable.server.pubsub.broadcasts(stream_name),
      "non-star updates should not emit star_change broadcasts"
  end

  test "star change on a direct-room membership does not broadcast" do
    membership = memberships(:david_david_and_jason)
    ActionCable.server.pubsub.clear

    # Bypass starred_only_for_shared_visible_rooms validation but keep callbacks
    # to exercise broadcast_star_change's room.direct? guard.
    membership.update_attribute(:starred, true)

    stream_name = "#{membership.user.to_gid_param}:rooms"
    assert_empty ActionCable.server.pubsub.broadcasts(stream_name),
      "star change on direct-room memberships should be guarded (room.direct?)"
  end

  test "star change on an invisible membership does not broadcast" do
    @membership.update!(involvement: :invisible)  # also auto-unstars via unstar_if_invisible
    ActionCable.server.pubsub.clear

    # Force a starred change while invisible — exercises broadcast_star_change's
    # involved_in_invisible? guard. Skip validations so unstar_if_invisible
    # doesn't undo the change before save.
    @membership.update_attribute(:starred, true)

    stream_name = "#{@membership.user.to_gid_param}:rooms"
    assert_empty ActionCable.server.pubsub.broadcasts(stream_name),
      "star change on invisible memberships should be guarded (involved_in_invisible?)"
  end
end
