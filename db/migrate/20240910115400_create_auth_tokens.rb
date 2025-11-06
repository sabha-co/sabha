class CreateAuthTokens < ActiveRecord::Migration[7.2]
  def change
    create_table :auth_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token
      t.string :code
      t.datetime :expires_at
      t.datetime :used_at

      t.timestamps
    end
  end
end
