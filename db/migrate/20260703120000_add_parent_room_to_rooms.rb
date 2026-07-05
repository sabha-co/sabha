class AddParentRoomToRooms < ActiveRecord::Migration[8.2]
  def up
    add_column :rooms, :parent_room_id, :integer

    # Denormalized FK from a thread to the room it was spawned in — the same
    # direct link messages have via room_id. Lets the forum gallery filter and
    # sort posts on the rooms table alone (no join to messages, no filesort).
    add_index :rooms, [ :parent_room_id, :active, :last_active_at ],
      name: "index_rooms_on_parent_room_and_activity", where: "parent_room_id IS NOT NULL"
    add_index :rooms, [ :parent_room_id, :active, :created_at ],
      name: "index_rooms_on_parent_room_and_created", where: "parent_room_id IS NOT NULL"

    execute <<~SQL
      UPDATE rooms
      SET parent_room_id = (SELECT messages.room_id FROM messages WHERE messages.id = rooms.parent_message_id)
      WHERE parent_message_id IS NOT NULL
    SQL
  end

  def down
    remove_column :rooms, :parent_room_id
  end
end
