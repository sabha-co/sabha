# frozen_string_literal: true

class CreateGlobalSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :global_sessions do |t|
      t.references :global_identity, null: false, foreign_key: true
      t.string :token, null: false
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_active_at
      t.datetime :expires_at

      t.timestamps

      t.index :token, unique: true
      t.index :expires_at
    end
  end
end
