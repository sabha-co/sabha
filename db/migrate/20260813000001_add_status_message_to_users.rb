class AddStatusMessageToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :status_message, :string
  end
end
