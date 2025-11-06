class MakeEmailsNonUnique < ActiveRecord::Migration[7.2]
  def change
    remove_index :users, :email_address, unique: true
    add_index :users, :email_address
  end
end
