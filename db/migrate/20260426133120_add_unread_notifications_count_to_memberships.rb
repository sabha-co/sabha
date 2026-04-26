class AddUnreadNotificationsCountToMemberships < ActiveRecord::Migration[7.2]
  def up
    add_column :memberships, :unread_notifications_count, :integer, default: 0, null: false

    # Backfill: only unread memberships can have a non-zero count.
    # For Direct rooms: every active message in the unread window counts.
    # For other rooms: messages mentioning this user OR @everyone messages count.
    Membership.unscoped.where.not(unread_at: nil).find_each do |membership|
      count = compute_count_for(membership)
      Membership.unscoped.where(id: membership.id).update_all(unread_notifications_count: count) if count > 0
    end
  end

  def down
    remove_column :memberships, :unread_notifications_count
  end

  private
    def compute_count_for(membership)
      room = Room.unscoped.find_by(id: membership.room_id)
      return 0 unless room

      # Match runtime semantics in Membership#count_unread_notifications_from,
      # which filters by Room#has_many :messages, -> { active }. Including
      # soft-deleted messages here would seed counts higher than the app
      # ever recomputes them.
      base = Message.where(room_id: membership.room_id, active: true)
                    .where("created_at >= ?", membership.unread_at)

      if room.type == "Rooms::Direct"
        base.count
      else
        base.where(
          "messages.mentions_everyone = ? OR EXISTS (" \
            "SELECT 1 FROM notifications WHERE notifications.message_id = messages.id " \
            "AND notifications.user_id = ? AND notifications.activity_type = 'mention')",
          true, membership.user_id
        ).count
      end
    end
end
