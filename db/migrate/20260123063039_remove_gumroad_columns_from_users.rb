class RemoveGumroadColumnsFromUsers < ActiveRecord::Migration[8.2]
  def change
    remove_index :users, :order_id, if_exists: true
    remove_column :users, :order_id, :bigint
    remove_column :users, :membership_started_at, :datetime
  end
end
