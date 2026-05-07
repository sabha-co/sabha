class AddUserActiveToWorkspaceMemberships < ActiveRecord::Migration[8.2]
  disable_ddl_transaction!

  def change
    # Denormalized mirror of the per-tenant User#active? — updated by the User
    # lifecycle methods (revoke_access, unban, reactivate) so the workspace
    # selector can filter without cross-tenant queries (activerecord-tenanted
    # forbids shard swapping inside an active tenant context).
    add_column :workspace_memberships, :user_active, :boolean, default: true, null: false
    add_index :workspace_memberships, [ :global_identity_id, :user_active ], algorithm: :concurrently
  end
end
