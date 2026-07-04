class RemoveSolvedAtFromRooms < ActiveRecord::Migration[8.2]
  def change
    remove_column :rooms, :solved_at, :datetime
  end
end
