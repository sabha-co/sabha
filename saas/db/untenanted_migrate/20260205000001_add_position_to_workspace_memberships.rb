# frozen_string_literal: true

class AddPositionToWorkspaceMemberships < ActiveRecord::Migration[8.0]
  def change
    add_column :workspace_memberships, :position, :integer
    add_index :workspace_memberships, [ :global_identity_id, :position ]
  end
end
