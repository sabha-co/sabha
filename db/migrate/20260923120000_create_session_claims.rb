class CreateSessionClaims < ActiveRecord::Migration[8.2]
  def change
    create_table :session_claims do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :nonce, null: false
      t.string :origin, null: false
      t.string :code_challenge, null: false
      t.string :return_path, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :session_claims, :token_digest, unique: true
    add_index :session_claims, :expires_at
  end
end
