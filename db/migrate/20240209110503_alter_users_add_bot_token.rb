class AlterUsersAddBotToken < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :bot_token, :string
    add_index :users, :bot_token, unique: true

    # Bot users do not use passwords
    change_column_null :users, :password_digest, true
  end
end
