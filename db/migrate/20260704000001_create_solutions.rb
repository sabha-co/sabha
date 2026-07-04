class CreateSolutions < ActiveRecord::Migration[8.2]
  def change
    create_table :solutions do |t|
      t.references :post, null: false, index: { unique: true }, foreign_key: { to_table: :rooms }
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
