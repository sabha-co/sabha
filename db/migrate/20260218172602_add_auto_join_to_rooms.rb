class AddAutoJoinToRooms < ActiveRecord::Migration[8.2]
  def change
    add_column :rooms, :auto_join, :boolean, default: false, null: false
  end
end
