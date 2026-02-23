class RemoveActiveFromBoostsAndBookmarks < ActiveRecord::Migration[8.2]
  def up
    # Remove orphaned soft-deleted records
    execute "DELETE FROM boosts WHERE active = 0"
    execute "DELETE FROM bookmarks WHERE active = 0"

    # Boosts: replace old indexes, add uniqueness constraint
    remove_index :boosts, name: "index_boosts_on_message_active_created"
    add_index :boosts, [ :message_id, :created_at ], name: "index_boosts_on_message_created"
    add_index :boosts, [ :message_id, :booster_id, :content ], unique: true, name: "index_boosts_on_message_booster_content"

    # Bookmarks: replace old index with unique constraint
    remove_index :bookmarks, name: "index_bookmarks_on_user_message_active"
    add_index :bookmarks, [ :user_id, :message_id ], unique: true, name: "index_bookmarks_on_user_message"

    remove_column :boosts, :active, :boolean, default: true
    remove_column :bookmarks, :active, :boolean, default: true
  end

  def down
    add_column :boosts, :active, :boolean, default: true
    add_column :bookmarks, :active, :boolean, default: true

    remove_index :boosts, name: "index_boosts_on_message_created"
    remove_index :boosts, name: "index_boosts_on_message_booster_content"
    add_index :boosts, [ :message_id, :active, :created_at ], name: "index_boosts_on_message_active_created"

    remove_index :bookmarks, name: "index_bookmarks_on_user_message"
    add_index :bookmarks, [ :user_id, :message_id, :active ], name: "index_bookmarks_on_user_message_active"
  end
end
