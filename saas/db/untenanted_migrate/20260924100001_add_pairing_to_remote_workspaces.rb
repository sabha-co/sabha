# frozen_string_literal: true

class AddPairingToRemoteWorkspaces < ActiveRecord::Migration[8.2]
  def change
    # A table added on this same release, with no rows in production yet
    safety_assured do
      change_table :remote_workspaces, bulk: true do |t|
        t.text :secret
        t.string :pairing_status, null: false, default: "none"
        t.string :paired_via
        t.references :paired_by, foreign_key: { to_table: :global_identities }
        t.datetime :paired_at
        t.datetime :last_signed_in_at
      end
    end
  end
end
