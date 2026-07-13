module UnreadTestHelper
  # Rewinds a membership's read cursor so `message` and everything after it
  # reads as unseen — the cursor equivalent of the legacy
  # `unread_at: message.created_at` setup.
  def rewind_unread_to(membership, message, marked: false)
    previous = membership.room.messages
                         .before_cursor(message.created_at, message.id)
                         .reorder(created_at: :desc, id: :desc).first
    membership.update_columns(
      last_read_at: previous&.created_at || Time.at(0),
      last_read_message_id: previous&.id || 0,
      marked_unread: marked
    )
  end

  # Rewinds to the beginning of time: every active message reads as unseen —
  # the cursor equivalent of the legacy `unread_at: 1.day.ago` setup.
  def force_all_unread(membership)
    membership.update_columns(last_read_at: Time.at(0), last_read_message_id: 0, marked_unread: false)
  end

  # Advances the cursor to the room's head: nothing reads as unseen — the
  # cursor equivalent of the legacy `unread_at: nil` setup.
  def catch_up(membership)
    head = membership.room.messages.reorder(:created_at, :id).last
    membership.update_columns(
      last_read_at: head&.created_at || Time.current,
      last_read_message_id: head&.id || 0,
      marked_unread: false
    )
  end
end
