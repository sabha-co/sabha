class AddActiveToMessages < ActiveRecord::Migration[7.2]
  def change
    add_column :messages, :active, :boolean, default: true
  end
end
