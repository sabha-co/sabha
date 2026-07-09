class AddReadCursorToMemberships < ActiveRecord::Migration[8.2]
  def up
    add_column :memberships, :last_read_at, :datetime
    add_column :memberships, :last_read_message_id, :integer
    add_column :memberships, :marked_unread, :boolean, default: false, null: false

    # One-time reset at cutover: every member starts caught up to their room's
    # head (or to now, in a room with no messages), so the next message dots
    # them. Legacy unread state is deliberately not carried over.
    execute <<~SQL.squish
      UPDATE memberships SET
        last_read_at = COALESCE(
          (SELECT m.created_at FROM messages m
            WHERE m.room_id = memberships.room_id AND m.active = TRUE
            ORDER BY m.created_at DESC, m.id DESC LIMIT 1),
          CURRENT_TIMESTAMP),
        last_read_message_id = COALESCE(
          (SELECT m.id FROM messages m
            WHERE m.room_id = memberships.room_id AND m.active = TRUE
            ORDER BY m.created_at DESC, m.id DESC LIMIT 1),
          0)
    SQL
  end

  def down
    remove_column :memberships, :marked_unread
    remove_column :memberships, :last_read_message_id
    remove_column :memberships, :last_read_at
  end
end
