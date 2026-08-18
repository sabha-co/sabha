class DropCustomStylesFromAccounts < ActiveRecord::Migration[8.2]
  def change
    remove_column :accounts, :custom_styles, :text
  end
end
