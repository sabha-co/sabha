class AddUniqueThreadIndexToRooms < ActiveRecord::Migration[7.2]
  def change
    # Remove the regular index on parent_message_id
    remove_index :rooms, :parent_message_id, if_exists: true

    # Add a unique partial index to ensure each message can only have one thread
    add_index :rooms, :parent_message_id,
              unique: true,
              where: "type = 'Rooms::Thread' AND parent_message_id IS NOT NULL",
              name: "index_rooms_on_parent_message_id_unique_thread"
  end
end
