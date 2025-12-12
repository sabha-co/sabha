class AddMustChangePasswordToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :must_change_password, :boolean, default: false, null: false
  end
end
