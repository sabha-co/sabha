class CreateSingleSignOnNonces < ActiveRecord::Migration[8.2]
  def change
    create_table :single_sign_on_nonces do |t|
      t.string :nonce, null: false
      t.string :return_path, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :single_sign_on_nonces, :nonce, unique: true
    add_index :single_sign_on_nonces, :expires_at
  end
end
