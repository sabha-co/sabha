class AddPerformanceIndexes < ActiveRecord::Migration[8.2]
  def change
    # For bookmarks lookup (used in Bookmark.populate_for)
    add_index :bookmarks, [ :user_id, :message_id, :active ],
              name: "index_bookmarks_on_user_message_active"

    # For boosts ordered by message (fixes Boost Load N+1)
    add_index :boosts, [ :message_id, :active, :created_at ],
              name: "index_boosts_on_message_active_created"

    # For message active filtering with room
    add_index :messages, [ :active, :room_id, :created_at ],
              name: "index_messages_on_active_room_created"
  end
end
