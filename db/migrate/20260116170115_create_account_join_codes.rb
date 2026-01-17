class CreateAccountJoinCodes < ActiveRecord::Migration[8.2]
  def up
    create_table :account_join_codes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true # nil = global/admin link
      t.string :code, null: false
      t.integer :usage_count, default: 0, null: false
      t.integer :usage_limit, null: true # nil = unlimited
      t.datetime :expires_at, null: true # nil = never expires

      t.timestamps
    end

    add_index :account_join_codes, :code, unique: true

    # Migrate existing join codes from accounts table
    execute <<~SQL
      INSERT INTO account_join_codes (account_id, code, usage_count, usage_limit, created_at, updated_at)
      SELECT id, join_code, 0, NULL, created_at, updated_at FROM accounts
    SQL

    remove_column :accounts, :join_code
  end

  def down
    add_column :accounts, :join_code, :string

    # Migrate join codes back to accounts table
    execute <<~SQL
      UPDATE accounts
      SET join_code = (SELECT code FROM account_join_codes WHERE account_join_codes.account_id = accounts.id LIMIT 1)
    SQL

    change_column_null :accounts, :join_code, false

    drop_table :account_join_codes
  end
end
