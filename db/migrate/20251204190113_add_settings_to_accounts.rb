class AddSettingsToAccounts < ActiveRecord::Migration[8.2]
  def change
    add_column :accounts, :settings, :json
  end
end
