class AddStarredToMemberships < ActiveRecord::Migration[8.2]
  def change
    add_column :memberships, :starred, :boolean, default: false, null: false
    add_index :memberships, [ :user_id, :starred ]
  end
end
