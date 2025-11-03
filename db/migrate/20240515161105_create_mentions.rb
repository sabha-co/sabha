class CreateMentions < ActiveRecord::Migration[7.2]
  def change
    create_table :mentions, id: false do |t|
      t.references :user, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
    end
  end
end
