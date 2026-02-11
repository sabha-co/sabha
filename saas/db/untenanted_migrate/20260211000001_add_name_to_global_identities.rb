class AddNameToGlobalIdentities < ActiveRecord::Migration[8.2]
  def change
    add_column :global_identities, :name, :string
  end
end
