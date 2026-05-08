class RemoveSlugFromWorkspaces < ActiveRecord::Migration[8.2]
  disable_ddl_transaction!

  def change
    remove_index :workspaces, name: "index_workspaces_on_slug", algorithm: :concurrently
    # Safe to drop in a single deploy: the column was never read or written by application code.
    safety_assured { remove_column :workspaces, :slug, :string }
  end
end
