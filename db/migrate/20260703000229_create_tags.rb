class CreateTags < ActiveRecord::Migration[8.2]
  def change
    create_table :tags do |t|
      t.references :room, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color
      t.timestamps
    end
    add_index :tags, [ :room_id, :name ], unique: true
  end
end
