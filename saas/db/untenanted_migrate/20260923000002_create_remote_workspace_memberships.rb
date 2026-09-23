# frozen_string_literal: true

class CreateRemoteWorkspaceMemberships < ActiveRecord::Migration[8.2]
  def change
    # A new, empty table: its two foreign keys block no existing writes.
    safety_assured do
      create_table :remote_workspace_memberships do |t|
        t.references :global_identity, null: false, foreign_key: true
        t.references :remote_workspace, null: false, index: false
        t.string :source, null: false
        t.integer :position
        t.boolean :hidden, null: false, default: false
        t.datetime :last_opened_at
        t.timestamps

        t.foreign_key :remote_workspaces
        t.index [ :remote_workspace_id, :global_identity_id ], unique: true,
          name: "index_remote_workspace_memberships_on_workspace_and_identity"
      end
    end
  end
end
