class RemoveReceivesFromWebhooks < ActiveRecord::Migration[8.2]
  def change
    remove_column :webhooks, :receives, :string

    remove_index :webhooks, :user_id
    add_index :webhooks, :user_id, unique: true
  end
end
