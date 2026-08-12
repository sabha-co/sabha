class AddUniqueIndexToMessagesClientMessageId < ActiveRecord::Migration[8.2]
  def change
    add_index :messages, :client_message_id, unique: true
  end
end
