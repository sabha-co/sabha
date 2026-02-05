# frozen_string_literal: true

class CreateWorkspaceExternalIdSequences < ActiveRecord::Migration[8.0]
  def change
    create_table :workspace_external_id_sequences do |t|
      t.bigint :value, null: false, default: 1_000_000

      t.index :value, unique: true
    end
  end
end
