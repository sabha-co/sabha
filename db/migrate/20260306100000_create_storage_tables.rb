class CreateStorageTables < ActiveRecord::Migration[8.2]
  def change
    create_table :storage_entries do |t|
      t.references :recordable, polymorphic: true
      t.references :blob, foreign_key: false
      t.bigint :delta, null: false
      t.string :operation, null: false
      t.references :user, foreign_key: false
      t.string :request_id
      t.datetime :created_at, null: false
    end

    create_table :storage_totals do |t|
      t.references :owner, polymorphic: true, null: false, index: { unique: true }
      t.bigint :bytes_stored, null: false, default: 0
      t.bigint :last_entry_id
      t.timestamps
    end
  end
end
