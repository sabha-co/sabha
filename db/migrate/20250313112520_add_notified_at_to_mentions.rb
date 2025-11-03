class AddNotifiedAtToMentions < ActiveRecord::Migration[7.2]
  def change
    add_column :mentions, :notified_at, :datetime
    add_index :mentions, [ :user_id, :message_id ]
    add_index :mentions, :user_id, where: "notified_at IS NULL", name: :index_mentions_on_user_id_and_not_notified
  end
end
