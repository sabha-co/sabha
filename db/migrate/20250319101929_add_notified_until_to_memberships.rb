class AddNotifiedUntilToMemberships < ActiveRecord::Migration[7.2]
  def change
    add_column :memberships, :notified_until, :datetime
    remove_index :mentions, :user_id, where: "notified_at IS NULL", name: :index_mentions_on_user_id_and_not_notified
    remove_column :mentions, :notified_at, :datetime
  end
end
