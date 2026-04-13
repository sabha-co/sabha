class RemoveRedundantIndexes < ActiveRecord::Migration[8.2]
  disable_ddl_transaction!

  def change
    # Redundant: covered by (global_identity_id, position) and (global_identity_id, tenant)
    remove_index :workspace_memberships, column: :global_identity_id, algorithm: :concurrently

    # Redundant: covered by (workspace_id, created_at)
    remove_index :workspace_backups, column: :workspace_id, algorithm: :concurrently
  end
end
