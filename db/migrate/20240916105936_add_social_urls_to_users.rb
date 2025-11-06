class AddSocialUrlsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :twitter_url, :string
    add_column :users, :linkedin_url, :string
  end
end
