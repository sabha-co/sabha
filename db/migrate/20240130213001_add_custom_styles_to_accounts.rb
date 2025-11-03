class AddCustomStylesToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :custom_styles, :text
  end
end
