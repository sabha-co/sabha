class AddStreakUpdatedOnToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :streak_updated_on, :date
  end
end
