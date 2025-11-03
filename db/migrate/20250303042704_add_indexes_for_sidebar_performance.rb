class AddIndexesForSidebarPerformance < ActiveRecord::Migration[7.2]
  def change
    # Add index for messages.room_id and messages.created_at to improve the performance of the
    # with_has_unread_notifications scope which uses these fields in its EXISTS subquery
    add_index :messages, [ :room_id, :created_at ], name: 'index_messages_on_room_id_and_created_at'

    # Add index for mentions.message_id and mentions.user_id to improve the JOIN performance
    # in the with_has_unread_notifications scope
    add_index :mentions, [ :message_id, :user_id ], name: 'index_mentions_on_message_id_and_user_id'

    # Add index for memberships.room_id and memberships.user_id to improve lookup performance
    add_index :memberships, [ :room_id, :user_id, :involvement ], name: 'index_memberships_on_room_user_involvement'
  end
end
