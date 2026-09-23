module Desktop
  class NotificationEvent
    attr_reader :message, :user, :activity_types

    # Builds every recipient's event up front — one push payload, one badge
    # query — so nothing is left to raise once delivery starts.
    def self.for_recipients(message:, user_ids:, activity_types:)
      return [] if user_ids.empty? || !Desktop.notifications_enabled?

      push_payload = Room::MessagePusher.payload_for(room: message.room, message: message)
      badges = Membership.badged.where(user_id: user_ids.to_a).group(:user_id).count

      User.where(id: user_ids.to_a).map do |user|
        new(message: message, user: user, activity_types: activity_types, push_payload: push_payload, badge: badges.fetch(user.id, 0))
      end
    end

    def self.event_id_for(message:, user:)
      parts = []
      parts << ApplicationRecord.current_tenant if Sabha.saas? && ApplicationRecord.current_tenant.present?
      parts << message.id
      parts << user.id
      parts.join(":")
    end

    def initialize(message:, user:, activity_types:, push_payload: nil, badge: nil)
      @message = message
      @user = user
      @activity_types = Array(activity_types).map(&:to_sym).uniq.sort
      @push_payload = push_payload
      @badge = badge
    end

    def event_id
      self.class.event_id_for(message: message, user: user)
    end

    # Best effort: runs after web pushes have gone out, so a failed broadcast
    # must not fail the dispatch job and re-send them on retry. The next badge
    # snapshot corrects the count.
    def deliver
      Rails.error.handle(context: { event_id: event_id }) do
        DesktopChannel.broadcast_to_user(user, as_json)
      end
    end

    def as_json
      {
        type: "notification",
        protocol_major: Desktop::PROTOCOL_MAJOR,
        event_id: event_id,
        message_id: message.id,
        activity_types: activity_types.map(&:to_s),
        title: push_payload.fetch(:title),
        body: push_payload.fetch(:body),
        path: push_payload.fetch(:path),
        badge: badge
      }
    end

    private
      def push_payload
        @push_payload ||= Room::MessagePusher.payload_for(room: message.room, message: message)
      end

      def badge
        @badge ||= user.badge_count
      end
  end
end
