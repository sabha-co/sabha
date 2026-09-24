# frozen_string_literal: true

class CreateRemoteWorkspacePairingRequests < ActiveRecord::Migration[8.2]
  def change
    # A new, empty table: its two foreign keys block no existing writes.
    safety_assured do
      create_table :remote_workspace_pairing_requests do |t|
        t.references :remote_workspace, null: false, foreign_key: true
        t.references :global_identity, null: false, index: false
        t.text :secret, null: false
        t.datetime :expires_at, null: false
        t.timestamps

        t.foreign_key :global_identities
        t.index :global_identity_id
      end
    end
  end
end
