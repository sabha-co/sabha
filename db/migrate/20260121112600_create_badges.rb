class CreateBadges < ActiveRecord::Migration[8.2]
  def change
    create_table :badges do |t|
      t.string :name, null: false
      t.string :icon
      t.string :color

      t.timestamps
    end

    add_index :badges, :name
    add_reference :users, :badge, foreign_key: true
  end
end
