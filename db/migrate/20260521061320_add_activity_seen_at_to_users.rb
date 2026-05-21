class AddActivitySeenAtToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :activity_seen_at, :datetime
  end
end
