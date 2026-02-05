# frozen_string_literal: true

class CreateGlobalIdentities < ActiveRecord::Migration[8.0]
  def change
    create_table :global_identities do |t|
      t.string :email_address, null: false
      t.datetime :verified_at

      t.timestamps

      t.index :email_address, unique: true
      t.index :verified_at
    end
  end
end
