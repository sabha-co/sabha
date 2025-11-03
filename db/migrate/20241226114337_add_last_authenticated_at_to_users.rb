class AddLastAuthenticatedAtToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :last_authenticated_at, :datetime
  end
end
