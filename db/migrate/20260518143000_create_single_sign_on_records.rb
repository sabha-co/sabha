class CreateSingleSignOnRecords < ActiveRecord::Migration[8.2]
  def change
    create_table :single_sign_on_records do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :external_id, null: false
      t.string :external_email
      t.text :last_payload
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :single_sign_on_records, :external_id, unique: true
  end
end
