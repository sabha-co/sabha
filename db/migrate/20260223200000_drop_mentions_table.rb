class DropMentionsTable < ActiveRecord::Migration[8.0]
  def up
    drop_table :mentions
  end

  def down
    create_table :mentions, id: false do |t|
      t.references :message, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
    end
    add_index :mentions, [:message_id, :user_id]
    add_index :mentions, [:user_id, :message_id]
  end
end
