class AddCreatorToSearches < ActiveRecord::Migration[7.2]
  def change
    add_reference :searches, :creator, null: true, foreign_key: { to_table: :users }
  end
end
