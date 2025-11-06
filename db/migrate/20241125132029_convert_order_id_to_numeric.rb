class ConvertOrderIdToNumeric < ActiveRecord::Migration[7.2]
  def change
    change_column :users, :order_id, :bigint
    add_index :users, :order_id, unique: true, where: 'order_id IS NOT NULL'
  end
end
