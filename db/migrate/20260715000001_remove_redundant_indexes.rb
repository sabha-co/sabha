class RemoveRedundantIndexes < ActiveRecord::Migration[8.2]
  # Each of these is the leftmost prefix of a wider composite, so lookups still
  # seek. The trade is lopsided rather than free: writes maintain fewer B-trees,
  # reads walk slightly wider index entries.
  #
  # A prefix is only redundant when the covering composite is unconditional: a
  # partial index can't serve a plain lookup. That's why notifications(message_id)
  # stays — its composite is partial, and dropping it forces a full scan.
  def change
    remove_index :account_join_codes, :account_id, name: "index_account_join_codes_on_account_id"
    remove_index :blocks, :blocker_id, name: "index_blocks_on_blocker_id"
    remove_index :bookmarks, :user_id, name: "index_bookmarks_on_user_id"
    remove_index :boosts, :message_id, name: "index_boosts_on_message_id"
    remove_index :memberships, :room_id, name: "index_memberships_on_room_id"
    remove_index :memberships, :user_id, name: "index_memberships_on_user_id"
    remove_index :messages, :room_id, name: "index_messages_on_room_id"
    remove_index :notification_bundle_items, :bundle_id, name: "index_notification_bundle_items_on_bundle_id"
    remove_index :notification_bundles, :user_id, name: "index_notification_bundles_on_user_id"

    # Not a prefix duplicate: (room_id, user_id) is unique, so a seek on it already
    # lands a single row and the trailing involvement column can never narrow it
    # further. The planner picks the unique index for these lookups regardless.
    remove_index :memberships, [ :room_id, :user_id, :involvement ], name: "index_memberships_on_room_user_involvement"
  end
end
