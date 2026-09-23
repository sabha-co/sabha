# frozen_string_literal: true

class CreateRemoteWorkspaces < ActiveRecord::Migration[8.2]
  def change
    create_table :remote_workspaces do |t|
      t.string :origin, null: false
      t.string :name, null: false
      t.string :alias_origin
      t.integer :protocol_major
      t.binary :logo_data
      t.string :logo_content_type
      t.string :logo_source_url
      t.datetime :refreshed_at
      t.datetime :unreachable_since
      t.timestamps

      t.index :origin, unique: true
    end
  end
end
