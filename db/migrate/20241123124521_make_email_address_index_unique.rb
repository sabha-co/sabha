class MakeEmailAddressIndexUnique < ActiveRecord::Migration[7.2]
  def change
    remove_index :users, :email_address
    add_index :users, :email_address, unique: true
  end
end
