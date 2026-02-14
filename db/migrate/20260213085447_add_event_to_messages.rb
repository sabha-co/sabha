class AddEventToMessages < ActiveRecord::Migration[8.2]
  def change
    add_column :messages, :event, :string
  end
end
