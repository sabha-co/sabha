class AddUnreadAtIndexToMemberships < ActiveRecord::Migration[8.2]
  def change
    # Optimizes queries like: user.memberships.visible.unread
    # Used in inbox queries and notification jobs
    add_index :memberships, [ :user_id, :unread_at ],
              where: "active = 1 AND unread_at IS NOT NULL",
              name: "index_memberships_on_user_unread_active"

    # Optimizes queries like: room.memberships.disconnected.read
    # Used in Room#unread_memberships when marking rooms as unread
    add_index :memberships, [ :room_id, :unread_at ],
              name: "index_memberships_on_room_unread"
  end
end
