class AddParentMessageToRooms < ActiveRecord::Migration[7.2]
  def change
    add_reference :rooms, :parent_message, null: true, foreign_key: { to_table: :messages }
  end
end
