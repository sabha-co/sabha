class CreateWorkspaceSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :workspace_snapshots do |t|
      t.references :workspace, null: false, foreign_key: true, index: { unique: true }
      t.integer :messages_24h, default: 0, null: false
      t.integer :messages_7d, default: 0, null: false
      t.integer :active_users, default: 0, null: false
      t.bigint :storage_bytes, default: 0, null: false
      t.bigint :database_size, default: 0, null: false
      t.timestamps
    end
  end
end
