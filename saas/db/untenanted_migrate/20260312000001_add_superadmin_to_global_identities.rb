# frozen_string_literal: true

class AddSuperadminToGlobalIdentities < ActiveRecord::Migration[8.2]
  def change
    add_column :global_identities, :superadmin, :boolean, default: false, null: false
    add_index :global_identities, :superadmin
  end
end
