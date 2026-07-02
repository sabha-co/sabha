class CreateTaggings < ActiveRecord::Migration[8.2]
  def change
    create_table :taggings do |t|
      t.references :tag, null: false, foreign_key: true, index: false
      t.references :room, null: false, foreign_key: true
      t.timestamps
    end
    add_index :taggings, [ :tag_id, :room_id ], unique: true
  end
end
