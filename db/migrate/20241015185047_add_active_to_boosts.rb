class AddActiveToBoosts < ActiveRecord::Migration[7.2]
  def change
    add_column :boosts, :active, :boolean, default: true
  end
end
