class AddSsoFieldsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :sso_user_id, :string
    add_column :users, :sso_token, :string
    add_column :users, :sso_token_expires_at, :datetime
    add_column :users, :avatar_url, :string
    add_column :users, :twitter_username, :string
    add_column :users, :linkedin_username, :string
    add_column :users, :personal_url, :string
    add_column :users, :membership_started_at, :datetime

    add_index :users, [ :active, :sso_user_id ], unique: true
  end
end
