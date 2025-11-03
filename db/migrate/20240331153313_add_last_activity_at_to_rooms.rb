class AddLastActivityAtToRooms < ActiveRecord::Migration[7.2]
  def change
    add_column :rooms, :last_active_at, :datetime
  end
end
