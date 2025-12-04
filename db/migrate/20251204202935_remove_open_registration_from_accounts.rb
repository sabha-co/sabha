class RemoveOpenRegistrationFromAccounts < ActiveRecord::Migration[8.2]
  def change
    remove_column :accounts, :open_registration, :boolean
  end
end
