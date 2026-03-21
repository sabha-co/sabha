# frozen_string_literal: true

class CreateWorkspaceBackups < ActiveRecord::Migration[8.2]
  def change
    create_table :workspace_backups do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :key, null: false
      t.bigint :size, null: false
      t.datetime :created_at, null: false
    end

    add_index :workspace_backups, :key, unique: true
    add_index :workspace_backups, [:workspace_id, :created_at]
  end
end
