require "test_helper"

class MessageTest < ActiveSupport::TestCase
  include ActionCable::TestHelper, ActiveJob::TestHelper

  test "client_message_id is auto-generated when not provided" do
    message = rooms(:pets).messages.create!(creator: users(:jason), body: "Hello")
    assert message.client_message_id.present?
    assert_match(/\A[0-9a-f-]+\z/, message.client_message_id) # UUID format
  end

  test "client_message_id is preserved when explicitly provided" do
    message = rooms(:pets).messages.create!(creator: users(:jason), body: "Hello", client_message_id: "custom-id")
    assert_equal "custom-id", message.client_message_id
  end

  test "creating a message enqueues a single Notification::DispatchJob" do
    assert_enqueued_jobs 1, only: [ Notification::DispatchJob ] do
      create_new_message_in rooms(:designers)
    end
  end

  # Event messages

  test "event? returns true when event is present" do
    message = Message.new(event: "room_renamed")
    assert message.event?
  end

  test "event? returns false for regular messages" do
    message = Message.new
    assert_not message.event?
  end

  test "without_events scope excludes event messages" do
    room = rooms(:pets)
    room.post_system_message(event: "room_renamed", body: "renamed", actor: users(:david))

    assert Message.unscoped.where(room: room).where.not(event: nil).exists?
    assert_not room.messages.without_events.where.not(event: nil).exists?
  end

  test "all emoji" do
    assert Message.new(body: "😄🤘").plain_text_body.all_emoji?
    assert_not Message.new(body: "Haha! 😄🤘").plain_text_body.all_emoji?
    assert_not Message.new(body: "🔥\nmultiple lines\n💯").plain_text_body.all_emoji?
    assert_not Message.new(body: "🔥 💯").plain_text_body.all_emoji?
  end

  test "mentionees" do
    message = Message.new room: rooms(:pets), body: "<div>Hey #{mention_attachment_for(:david)}</div>", creator: users(:jason), client_message_id: "earth"
    assert_equal [ users(:david) ], message.mentionees

    message_with_duplicate_mentions = Message.new room: rooms(:pets), body: "<div>Hey #{mention_attachment_for(:david)} #{mention_attachment_for(:david)}</div>", creator: users(:jason), client_message_id: "earth"
    assert_equal [ users(:david) ], message.mentionees

    message_mentioning_a_non_member = Message.new room: rooms(:pets), body: "<div>Hey #{mention_attachment_for(:kevin)}</div>", creator: users(:jason), client_message_id: "earth"
    assert_equal [], message_mentioning_a_non_member.mentionees
  end

  test "deactivating message clears unread timestamps pointing to it" do
    room = rooms(:pets)
    user = users(:david)
    membership = room.memberships.find_by(user: user)

    # Create two messages
    message1 = room.messages.create!(creator: users(:jason), body: "First message", client_message_id: "msg1")
    message2 = room.messages.create!(creator: users(:jason), body: "Second message", client_message_id: "msg2")

    # Mark membership as unread at message1
    membership.update!(unread_at: message1.created_at)
    assert membership.unread?
    assert_equal message1.created_at, membership.unread_at

    # Deactivate message1
    message1.deactivate

    # Should update unread_at to message2 since it's the next unread message
    membership.reload
    assert membership.unread?
    assert_equal message2.created_at, membership.unread_at
  end

  test "deactivating last unread message marks membership as read" do
    room = rooms(:pets)
    user = users(:david)
    membership = room.memberships.find_by(user: user)

    # Create one message
    message = room.messages.create!(creator: users(:jason), body: "Only message", client_message_id: "msg1")

    # Mark membership as unread at this message
    membership.update!(unread_at: message.created_at)
    assert membership.unread?

    # Deactivate the message
    message.deactivate

    # Should mark membership as read since no unread messages remain
    membership.reload
    assert membership.read?
    assert_nil membership.unread_at
  end

  test "deactivating message only affects memberships with matching unread_at" do
    room = rooms(:pets)
    user1 = users(:david)
    user2 = users(:jason)
    membership1 = room.memberships.find_by(user: user1)
    membership2 = room.memberships.find_by(user: user2)

    # Create two messages
    message1 = room.messages.create!(creator: users(:jason), body: "First message", client_message_id: "msg1")
    message2 = room.messages.create!(creator: users(:jason), body: "Second message", client_message_id: "msg2")

    # Mark memberships with different unread_at timestamps
    membership1.update!(unread_at: message1.created_at)
    membership2.update!(unread_at: message2.created_at)

    # Deactivate message1
    message1.deactivate

    # Only membership1 should be affected
    membership1.reload
    membership2.reload

    assert_equal message2.created_at, membership1.unread_at  # Updated to next message
    assert_equal message2.created_at, membership2.unread_at  # Unchanged
  end

  test "@everyone mention sets mentions_everyone flag" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div>Hey <action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    admin = users(:jason)  # jason is already an administrator

    message = Message.create!(
      room: rooms(:pets),
      body: body_html,
      creator: admin,
      client_message_id: "test123"
    )

    assert message.mentions_everyone?
  end

  test "@everyone returns all room users as mentionees" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    admin = users(:jason)  # jason is already an administrator

    room = rooms(:pets)
    message = Message.create!(
      room: room,
      body: body_html,
      creator: admin,
      client_message_id: "test456"
    )

    assert_equal room.users.count, message.mentionees.count
    assert_includes message.mentionees, users(:david)
  end

  test "only admins can use @everyone" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    non_admin = users(:jz)  # jz is not an administrator

    message = Message.new(
      room: rooms(:pets),
      body: body_html,
      creator: non_admin,
      client_message_id: "test789"
    )

    assert_not message.valid?
    assert_includes message.errors[:base], "Only admins can mention @everyone"
  end

  test "@everyone only allowed in open rooms" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    admin = users(:jason)  # jason is already an administrator

    # Test that @everyone is not allowed in direct messages
    direct_room = rooms(:david_and_jason)
    message = Message.new(
      room: direct_room,
      body: body_html,
      creator: admin,
      client_message_id: "test999"
    )

    assert_not message.valid?
    assert_includes message.errors[:base], "@everyone is only allowed in open rooms"
  end

  test "Message.mentioning scope includes @everyone messages" do
    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    admin = users(:jason)  # jason is already an administrator

    room = rooms(:pets)
    message = Message.create!(
      room: room,
      body: body_html,
      creator: admin,
      client_message_id: "scope_test"
    )

    user = users(:david)
    mentioning_messages = Message.where(room: room).mentioning(user.id)

    assert_includes mentioning_messages, message
  end

  test "destroying a parent message destroys its thread rooms" do
    room = rooms(:pets)

    # Create a message that will be the parent of a thread
    parent_message = room.messages.create!(body: "Parent message", creator: users(:jason), client_message_id: "parent123")

    # Create a thread from that message
    thread = Rooms::Thread.create!(parent_message: parent_message, creator: users(:jason))
    thread.memberships.grant_to(users(:jason))
    thread_message = thread.messages.create!(body: "Thread reply", creator: users(:jason), client_message_id: "thread123")

    thread_id = thread.id
    thread_message_id = thread_message.id

    # Destroy the parent message
    parent_message.destroy

    # Thread room and its messages should be destroyed
    assert_not Rooms::Thread.exists?(thread_id), "Thread room should be destroyed when parent message is destroyed"
    assert_not Message.exists?(thread_message_id), "Thread messages should be destroyed when thread is destroyed"
  end

  test "attachment with allowed content type is valid" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("hello"), filename: "note.txt", content_type: "text/plain"
    )

    message = rooms(:pets).messages.new(
      creator: users(:jason), body: "See attached", client_message_id: "allowed-type"
    )
    message.attachment.attach(blob)

    assert message.valid?
  end

  test "attachment with disallowed content type is invalid" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("MZ..."), filename: "malware.exe", content_type: "application/x-msdownload"
    )

    message = rooms(:pets).messages.new(
      creator: users(:jason), body: "See attached", client_message_id: "bad-type"
    )
    message.attachment.attach(blob)

    assert_not message.valid?
    assert_includes message.errors[:attachment], "type is not allowed"
  end

  test "attachment exceeding max size is invalid" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x" * 1024), filename: "big.txt", content_type: "text/plain"
    )
    # Fake the byte_size to exceed the limit without creating a huge file
    blob.update_column(:byte_size, 51.megabytes)

    message = rooms(:pets).messages.new(
      creator: users(:jason), body: "See attached", client_message_id: "too-big"
    )
    message.attachment.attach(blob)

    assert_not message.valid?
    assert_includes message.errors[:attachment], "is too large (max 50MB)"
  end

  # Welcome messages

  test "welcome? returns true for welcome messages" do
    message = Message.new(welcome: true)
    assert message.welcome?
    assert_not message.event?
  end

  test "welcome? returns false for events and regular messages" do
    assert_not Message.new(event: "member_joined").welcome?
    assert_not Message.new(event: "room_renamed").welcome?
    assert_not Message.new.welcome?
  end

  test "repliable? is true for regular and welcome messages but false for events" do
    assert Message.new.repliable?
    assert Message.new(welcome: true).repliable?
    assert_not Message.new(event: "member_joined").repliable?
    assert_not Message.new(event: "room_renamed").repliable?
  end

  test "welcome message does not update creator streak" do
    user = users(:rachel)
    user.update_column(:current_streak, 0)

    rooms(:hq).post_welcome_message(user: user)

    assert_equal 0, user.reload.current_streak
  end

  test "mentioning a non-member does not add them to the room" do
    room = rooms(:pets)
    jz = users(:jz)

    assert_not room.memberships.exists?(user: jz)

    room.messages.create!(
      body: "<div>Hey #{mention_attachment_for(:jz)}</div>",
      creator: users(:jason),
      client_message_id: "no_involve_1"
    )

    assert_not room.memberships.exists?(user: jz), "Non-member should not be added to room via mention"
  end

  test "thread_fingerprint rotates when a thread is created on the message" do
    message = rooms(:watercooler).messages.create!(creator: users(:david), body: "Hello", client_message_id: "fp-1")

    before = message.thread_fingerprint

    Current.set(user: users(:david)) do
      Rooms::Thread.find_or_create_for(message, users: rooms(:watercooler).users)
        .messages.create!(body: "Reply", creator: users(:david), client_message_id: "fp-2")
    end

    assert_not_equal before, message.reload.thread_fingerprint
  end

  # boost_summary

  test "boost_summary aggregates boosts by content with counts and boosters" do
    message = messages(:bender_message)
    message.boosts.create!(content: "🚀", booster: users(:jason))
    message.boosts.create!(content: "🚀", booster: users(:david))
    message.boosts.create!(content: "❤️", booster: users(:jz))

    groups, total, truncated = message.boost_summary

    assert_equal 3, total
    assert_equal false, truncated
    assert_equal [ "🚀", "❤️" ], groups.map(&:content)

    rocket = groups.first
    assert_equal 2, rocket.count
    assert_equal false, rocket.truncated
    assert_equal [ users(:jason), users(:david) ], rocket.boosters
  end

  test "boost_summary sorts groups by count DESC then earliest reaction ASC" do
    message = messages(:bender_message)
    Boost.create!(message: message, booster: users(:jz),     content: "❤️", created_at: 1.hour.ago)
    Boost.create!(message: message, booster: users(:david),  content: "👍", created_at: 30.minutes.ago)
    Boost.create!(message: message, booster: users(:jason),  content: "👍", created_at: 5.minutes.ago)
    Boost.create!(message: message, booster: users(:rachel), content: "🚀", created_at: 20.minutes.ago)
    Boost.create!(message: message, booster: users(:nsa),    content: "🚀", created_at: 10.minutes.ago)

    groups, _total, _truncated = message.boost_summary
    assert_equal [ "👍", "🚀", "❤️" ], groups.map(&:content)
  end

  test "boost_summary sorts boosters within a group oldest-first" do
    message = messages(:bender_message)
    Boost.create!(message: message, booster: users(:jason), content: "🚀", created_at: 30.minutes.ago)
    Boost.create!(message: message, booster: users(:david), content: "🚀", created_at: 20.minutes.ago)
    Boost.create!(message: message, booster: users(:jz),    content: "🚀", created_at: 10.minutes.ago)

    groups, _total, _truncated = message.boost_summary
    assert_equal [ users(:jason), users(:david), users(:jz) ], groups.first.boosters
  end

  test "boost_summary truncates boosters past boosters_limit and sets per-group truncated flag" do
    message = messages(:bender_message)
    %i[ jason david jz rachel ].each do |handle|
      message.boosts.create!(booster: users(handle), content: "🚀")
    end

    groups, total, truncated = message.boost_summary(limit: 10, boosters_limit: 2)
    rocket = groups.first
    assert_equal 4, rocket.count
    assert_equal 2, rocket.boosters.size
    assert rocket.truncated
    assert_equal 4, total
    assert_equal false, truncated, "top-level truncated tracks groups cap, not boosters cap"
  end

  test "boost_summary truncates groups past limit and sets top-level truncated flag" do
    message = messages(:bender_message)
    %w[ 🚀 ❤️ 👍 🎉 ].each do |emoji|
      message.boosts.create!(booster: users(:jason), content: emoji)
    end

    groups, total, truncated = message.boost_summary(limit: 2, boosters_limit: 100)
    assert_equal 2, groups.size
    assert truncated
    assert_equal 4, total
  end

  test "boost_summary returns empty result when no boosts exist" do
    message = messages(:bender_message)

    groups, total, truncated = message.boost_summary
    assert_equal [], groups
    assert_equal 0, total
    assert_equal false, truncated
  end

  # ----- Email bundle candidates (U5) -----

  test "mention to an away user with all flags on creates a kind=mention BundleItem" do
    enable_email_path!(users(:jason))

    assert_difference -> { Notification::BundleItem.count }, 1 do
      perform_enqueued_jobs(only: Notification::DispatchJob) do
        rooms(:designers).messages.create!(
          body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
          creator: users(:david),
          client_message_id: "u5_mention_happy"
        )
      end
    end

    item = Notification::BundleItem.last
    assert_equal "mention",        item.kind
    assert_equal users(:jason).id, item.bundle.user_id
    assert_equal users(:david).id, item.actor_id
  end

  test "@everyone in an open room creates kind=mention BundleItems for every away room member who would receive an in-app row" do
    rooms(:pets).user_ids.each do |uid|
      next if uid == users(:david).id
      User.find(uid).create_notification_settings!(missed_email_enabled: true) unless User.find(uid).notification_settings
    end
    Account.sole.update!(email_notifications_enabled: true)

    everyone_sgid = Everyone.new.attachable_sgid
    body_html = "<div><action-text-attachment sgid=\"#{everyone_sgid}\" content-type=\"application/vnd.sabha.mention\"></action-text-attachment></div>"

    perform_enqueued_jobs(only: Notification::DispatchJob) do
      Message.create!(
        room: rooms(:pets),
        body: body_html,
        creator: users(:david),
        client_message_id: "u5_everyone"
      )
    end

    eligible_user_ids = (rooms(:pets).user_ids - [ users(:david).id ]).sort
    assert_equal eligible_user_ids,
      Notification::BundleItem.where(kind: "mention").joins(:bundle).pluck("notification_bundles.user_id").sort
  end

  test "DM to an away user creates a kind=direct_message BundleItem" do
    enable_email_path!(users(:david))

    assert_difference -> { Notification::BundleItem.count }, 1 do
      perform_enqueued_jobs(only: Notification::DispatchJob) do
        rooms(:david_and_jason).messages.create!(
          body: "Hey",
          creator: users(:jason),
          client_message_id: "u5_dm_happy"
        )
      end
    end

    item = Notification::BundleItem.last
    assert_equal "direct_message", item.kind
    assert_equal users(:david).id, item.bundle.user_id
  end

  test "multiple mentions in the same window land in the same bundle" do
    enable_email_path!(users(:jason))

    perform_enqueued_jobs(only: Notification::DispatchJob) do
      rooms(:designers).messages.create!(
        body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
        creator: users(:david),
        client_message_id: "u5_same_window_1"
      )
      rooms(:designers).messages.create!(
        body: "<div>Again #{mention_attachment_for(:jason)}</div>",
        creator: users(:david),
        client_message_id: "u5_same_window_2"
      )
    end

    bundles = Notification::Bundle.where(user_id: users(:jason).id)
    assert_equal 1, bundles.count
    assert_equal 2, Notification::BundleItem.where(bundle_id: bundles.first.id).count
  end

  test "bundle frequency reflects the user's preference at creation; later flips don't move the bundle" do
    enable_email_path!(users(:jason))
    users(:jason).notification_settings.update!(email_frequency: :hourly)

    perform_enqueued_jobs(only: Notification::DispatchJob) do
      rooms(:designers).messages.create!(
        body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
        creator: users(:david),
        client_message_id: "u5_freq_snapshot_1"
      )
    end

    bundle = Notification::Bundle.find_by!(user_id: users(:jason).id)
    assert_equal "hourly", bundle.frequency
    original_ends_at = bundle.ends_at

    users(:jason).notification_settings.update!(email_frequency: :daily)
    perform_enqueued_jobs(only: Notification::DispatchJob) do
      rooms(:designers).messages.create!(
        body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
        creator: users(:david),
        client_message_id: "u5_freq_snapshot_2"
      )
    end

    bundle.reload
    assert_equal "hourly", bundle.frequency
    assert_in_delta original_ends_at, bundle.ends_at, 1.second
  end

  test "mention to a non-away user creates no bundle item" do
    enable_email_path!(users(:jason))
    memberships(:jason_designers).update!(connected_at: Time.current)

    assert_no_difference -> { Notification::BundleItem.count } do
      perform_enqueued_jobs(only: Notification::DispatchJob) do
        rooms(:designers).messages.create!(
          body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
          creator: users(:david),
          client_message_id: "u5_not_away"
        )
      end
    end
  end

  test "mention with account.email_notifications_enabled = false creates no bundle item" do
    users(:jason).create_notification_settings!(missed_email_enabled: true)
    Account.sole.update!(email_notifications_enabled: false)

    assert_no_difference -> { Notification::BundleItem.count } do
      perform_enqueued_jobs(only: Notification::DispatchJob) do
        rooms(:designers).messages.create!(
          body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
          creator: users(:david),
          client_message_id: "u5_account_off"
        )
      end
    end
  end

  test "mention with user's missed_email_enabled = false creates no bundle item" do
    Account.sole.update!(email_notifications_enabled: true)
    users(:jason).create_notification_settings!(missed_email_enabled: false)

    assert_no_difference -> { Notification::BundleItem.count } do
      perform_enqueued_jobs(only: Notification::DispatchJob) do
        rooms(:designers).messages.create!(
          body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
          creator: users(:david),
          client_message_id: "u5_user_off"
        )
      end
    end
  end

  test "blocked-sender mention creates no bundle item" do
    enable_email_path!(users(:jason))
    users(:jason).block!(users(:david))

    assert_no_difference -> { Notification::BundleItem.count } do
      perform_enqueued_jobs(only: Notification::DispatchJob) do
        rooms(:designers).messages.create!(
          body: "<div>Hey #{mention_attachment_for(:jason)}</div>",
          creator: users(:david),
          client_message_id: "u5_blocked"
        )
      end
    end
  end

  test "everyone_room_message without a mention produces no bundle items (not in EMAIL_TYPES)" do
    enable_email_path!(users(:jason))
    enable_email_path!(users(:jz))

    assert_no_difference -> { Notification::BundleItem.count } do
      perform_enqueued_jobs(only: Notification::DispatchJob) do
        rooms(:designers).messages.create!(
          body: "no mentions, just a regular open-room broadcast",
          creator: users(:david),
          client_message_id: "u5_everyone_room"
        )
      end
    end
  end

  test "thread_reply produces no bundle items (not in EMAIL_TYPES)" do
    enable_email_path!(users(:jason))

    parent = rooms(:designers).messages.create!(
      body: "thread root", creator: users(:david), client_message_id: "u5_thread_root"
    )
    thread = Rooms::Thread.create!(parent_message: parent, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason) ])

    assert_no_difference -> { Notification::BundleItem.count } do
      perform_enqueued_jobs(only: Notification::DispatchJob) do
        thread.messages.create!(
          body: "reply", creator: users(:david), client_message_id: "u5_thread_reply"
        )
      end
    end
  end

  private
    def create_new_message_in(room)
      room.messages.create!(creator: users(:jason), body: "Hello", client_message_id: "123")
    end

    def enable_email_path!(user)
      Account.sole.update!(email_notifications_enabled: true)
      user.notification_settings&.update!(missed_email_enabled: true) ||
        user.create_notification_settings!(missed_email_enabled: true)
      # Fixtures default connected_at to nil → workspace_locally_away? is true.
    end
end
