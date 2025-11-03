class IndexMessagesOnCreatedAt < ActiveRecord::Migration[7.2]
  def change
    add_index :messages, :created_at
  end
end
