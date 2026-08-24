class AddPresenceToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :availability, :integer, default: 0, null: false
    add_column :users, :last_active_at, :datetime
  end
end
