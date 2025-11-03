class AddActiveToRooms < ActiveRecord::Migration[7.2]
  def change
    add_column :rooms, :active, :boolean, default: true
  end
end
