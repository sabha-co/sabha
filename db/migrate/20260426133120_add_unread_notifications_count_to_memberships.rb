class AddUnreadNotificationsCountToMemberships < ActiveRecord::Migration[7.2]
  def up
    add_column :memberships, :unread_notifications_count, :integer, default: 0, null: false

    # Backfill in raw SQL so this works both in single-tenant Rails db:migrate
    # and in per-tenant SaaS migrations (which run through with_temporary_connection
    # without setting an Active Record tenant context, so AR model lookups would
    # raise NoTenantError).
    #
    # Mirrors the runtime semantics of Membership#count_unread_notifications_from:
    # only active messages count; for direct rooms every message counts; for
    # other rooms only mentions and @everyone count.
    execute <<~SQL.squish
      UPDATE memberships
      SET unread_notifications_count = (
        SELECT COUNT(*)
        FROM messages
        WHERE messages.room_id = memberships.room_id
          AND messages.active = #{quoted_true}
          AND messages.created_at >= memberships.unread_at
          AND (
            EXISTS (
              SELECT 1 FROM rooms
              WHERE rooms.id = memberships.room_id
                AND rooms.type = 'Rooms::Direct'
            )
            OR messages.mentions_everyone = #{quoted_true}
            OR EXISTS (
              SELECT 1 FROM notifications
              WHERE notifications.message_id = messages.id
                AND notifications.user_id = memberships.user_id
                AND notifications.activity_type = 'mention'
            )
          )
      )
      WHERE unread_at IS NOT NULL
    SQL
  end

  def down
    remove_column :memberships, :unread_notifications_count
  end

  private
    def quoted_true
      connection.quoted_true
    end
end
