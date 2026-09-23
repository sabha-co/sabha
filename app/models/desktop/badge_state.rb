module Desktop
  class BadgeState
    PROTOCOL_MAJOR = 1

    class << self
      def enabled?
        Rails.application.config.x.desktop_notifications_enabled
      end

      def count_for(user)
        user.memberships.unread.where("unread_notifications_count > 0").count
      end

      # { user_id => count } in one query; users with nothing unread are absent.
      def counts_for(user_ids)
        Membership.where(user_id: user_ids.to_a).unread.where("unread_notifications_count > 0").group(:user_id).count
      end

      def snapshot_for(user)
        {
          type: "badge",
          protocol_major: PROTOCOL_MAJOR,
          count: count_for(user)
        }
      end

      def broadcast_to(user)
        return unless enabled?

        DesktopChannel.broadcast_to_user(user, snapshot_for(user))
      end

      def broadcast_to_users(users)
        users.uniq.each { |user| broadcast_to(user) }
      end
    end
  end
end
