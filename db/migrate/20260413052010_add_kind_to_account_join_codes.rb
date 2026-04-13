class AddKindToAccountJoinCodes < ActiveRecord::Migration[8.2]
  def change
    add_column :account_join_codes, :kind, :string, default: "human", null: false
    add_index :account_join_codes, [ :account_id, :kind ]
  end
end
