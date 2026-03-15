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

  test "creating a message enqueues to push later" do
    assert_enqueued_jobs 1, only: [ Room::PushMessageJob ] do
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

  test "welcome? returns true for member_welcomed event" do
    message = Message.new(event: "member_welcomed")
    assert message.welcome?
    assert message.event?
  end

  test "welcome? returns false for other events" do
    assert_not Message.new(event: "member_joined").welcome?
    assert_not Message.new(event: "room_renamed").welcome?
    assert_not Message.new.welcome?
  end

  test "repliable? is true for regular messages and welcome events but false for other events" do
    assert Message.new.repliable?
    assert Message.new(event: "member_welcomed").repliable?
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

  private
    def create_new_message_in(room)
      room.messages.create!(creator: users(:jason), body: "Hello", client_message_id: "123")
    end
end
