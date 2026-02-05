# frozen_string_literal: true

class CreateWorkspaces < ActiveRecord::Migration[8.0]
  def change
    create_table :workspaces do |t|
      t.bigint :external_id, null: false
      t.string :name, null: false
      t.references :creator, null: false, foreign_key: { to_table: :global_identities }
      t.datetime :suspended_at

      t.timestamps

      t.index :external_id, unique: true
      t.index :suspended_at
    end
  end
end
