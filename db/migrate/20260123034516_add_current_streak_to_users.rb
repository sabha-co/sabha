class AddCurrentStreakToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :current_streak, :integer, default: 0, null: false
  end
end
