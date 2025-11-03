class AddOrderIdToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :order_id, :string
  end
end
