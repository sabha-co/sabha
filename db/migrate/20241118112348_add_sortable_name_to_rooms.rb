class AddSortableNameToRooms < ActiveRecord::Migration[7.2]
  def change
    add_column :rooms, :sortable_name, :string
  end
end
