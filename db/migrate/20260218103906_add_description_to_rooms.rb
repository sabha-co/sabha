class AddDescriptionToRooms < ActiveRecord::Migration[8.2]
  def change
    add_column :rooms, :description, :text
  end
end
