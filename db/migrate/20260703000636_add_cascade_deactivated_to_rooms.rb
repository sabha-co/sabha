class AddCascadeDeactivatedToRooms < ActiveRecord::Migration[8.2]
  def change
    add_column :rooms, :cascade_deactivated, :boolean, default: false, null: false
  end
end
