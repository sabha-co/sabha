class AddActiveToMemberships < ActiveRecord::Migration[7.2]
  def change
    add_column :memberships, :active, :boolean, default: true
  end
end
