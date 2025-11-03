class AddSuspendedAtToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :suspended_at, :datetime
  end
end
