class CreateNotifications < ActiveRecord::Migration[8.2]
  def change
    create_table :notifications do |t|
      t.integer  :user_id,       null: false
      t.integer  :message_id,    null: false
      t.integer  :actor_id,      null: false
      t.string   :activity_type, null: false
      t.integer  :boost_id
      t.timestamps
    end

    add_index :notifications, [ :user_id, :created_at ],
              name: "index_notifications_on_user_created"
    add_index :notifications, [ :message_id, :user_id, :activity_type ],
              name: "index_notifications_on_message_user_type",
              unique: true,
              where: "boost_id IS NULL"
    add_index :notifications, [ :message_id ],
              name: "index_notifications_on_message_id"
    add_index :notifications, [ :boost_id ],
              name: "index_notifications_on_boost_id",
              where: "boost_id IS NOT NULL"
    add_index :notifications, [ :actor_id ],
              name: "index_notifications_on_actor_id"

    add_foreign_key :notifications, :users
    add_foreign_key :notifications, :messages
    add_foreign_key :notifications, :users, column: :actor_id
    add_foreign_key :notifications, :boosts
  end
end
