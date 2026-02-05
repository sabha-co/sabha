# frozen_string_literal: true

class CreateAuthCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :auth_codes do |t|
      t.references :global_identity, null: false, foreign_key: true
      t.string :code, null: false
      t.integer :purpose, null: false, default: 0
      t.datetime :expires_at, null: false

      t.timestamps

      t.index :code, unique: true
      t.index :expires_at
    end
  end
end
