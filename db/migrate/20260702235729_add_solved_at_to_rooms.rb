class AddSolvedAtToRooms < ActiveRecord::Migration[8.2]
  def change
    add_column :rooms, :solved_at, :datetime
  end
end
