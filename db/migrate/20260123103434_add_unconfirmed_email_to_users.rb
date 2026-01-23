class AddUnconfirmedEmailToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :unconfirmed_email, :string
  end
end
