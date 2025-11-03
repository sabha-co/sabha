class CreateBlocks < ActiveRecord::Migration[7.2]
  def change
    create_table :blocks do |t|
      t.references :blocker, null: false, foreign_key: { to_table: :users }
      t.references :blocked, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :blocks, [ :blocker_id, :blocked_id ], unique: true
  end
end
