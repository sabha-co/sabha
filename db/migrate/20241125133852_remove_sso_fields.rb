class RemoveSsoFields < ActiveRecord::Migration[7.2]
  def change
    remove_index :users, [ :active, :sso_user_id ]
    remove_column :users, :sso_user_id, :string
    remove_column :users, :sso_token, :string
    remove_column :users, :sso_token_expires_at, :datetime
  end
end
