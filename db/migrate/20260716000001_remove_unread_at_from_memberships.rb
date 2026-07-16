class RemoveUnreadAtFromMemberships < ActiveRecord::Migration[8.2]
  # unread_at was the per-member unread flag written in bulk on every send. The
  # read cursor (last_read_at, last_read_message_id, marked_unread) replaced it
  # and nothing has read or written the column since. Its indexes go first:
  # SQLite's native DROP COLUMN refuses while the column is indexed.
  def change
    remove_index :memberships, [ :room_id, :unread_at ], name: "index_memberships_on_room_unread"
    remove_index :memberships, [ :user_id, :unread_at ], name: "index_memberships_on_user_unread_active",
                 where: "active = 1 AND unread_at IS NOT NULL"
    remove_column :memberships, :unread_at, :datetime
  end
end
