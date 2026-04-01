class RemoveReceivesFromWebhooks < ActiveRecord::Migration[8.2]
  def up
    # Collapse duplicate webhook rows per bot: keep the mentions webhook (or first row)
    # before adding the unique index. Bots could have had both a mentions and everything webhook.
    execute <<~SQL.squish
      DELETE FROM webhooks WHERE id NOT IN (
        SELECT MIN(id) FROM webhooks GROUP BY user_id
      )
    SQL

    remove_column :webhooks, :receives, :string

    remove_index :webhooks, :user_id
    add_index :webhooks, :user_id, unique: true
  end

  def down
    remove_index :webhooks, :user_id
    add_index :webhooks, :user_id

    add_column :webhooks, :receives, :string, default: "mentions"
  end
end
