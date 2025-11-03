class RemoveOwnerRole < ActiveRecord::Migration[7.2]
  def change
    # Migrate existing owner to administrator
    execute "update users set role = 1 where role = 2"
  end
end
