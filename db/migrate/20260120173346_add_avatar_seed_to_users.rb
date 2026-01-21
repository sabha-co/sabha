class AddAvatarSeedToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :avatar_seed, :integer
  end
end
