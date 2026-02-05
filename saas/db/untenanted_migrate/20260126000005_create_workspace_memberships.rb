# frozen_string_literal: true

class CreateWorkspaceMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :workspace_memberships do |t|
      t.references :global_identity, null: false, foreign_key: true
      t.string :tenant, null: false
      t.bigint :user_id  # Cached User ID from tenanted database

      t.timestamps

      t.index [ :global_identity_id, :tenant ], unique: true
      t.index :tenant
    end
  end
end
