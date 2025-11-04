class AddAdminSettingsToAccount < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :auth_method, :string, default: "password"
    add_column :accounts, :open_registration, :boolean, default: false
  end
end
