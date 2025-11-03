class AddAsciiNameToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :ascii_name, :string
  end
end
