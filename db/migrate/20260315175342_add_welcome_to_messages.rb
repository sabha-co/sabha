class AddWelcomeToMessages < ActiveRecord::Migration[8.2]
  def change
    add_column :messages, :welcome, :boolean, default: false, null: false
  end
end
