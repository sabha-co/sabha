class MakeMessagesAnswereable < ActiveRecord::Migration[7.2]
  def change
    change_table :messages do |t|
      t.datetime :answered_at, index: true
      t.references :answered_by, null: true, foreign_key: { to_table: :users }
    end
  end
end
