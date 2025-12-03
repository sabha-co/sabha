class RemoveCircularForeignKeys < ActiveRecord::Migration[8.0]
  def change
    # Remove circular FK: rooms -> messages creates a cycle with messages -> rooms
    # This prevents schema.rb from loading properly
    remove_foreign_key :rooms, :messages, column: :parent_message_id, if_exists: true
  end
end
