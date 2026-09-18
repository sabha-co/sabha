module Desktop
  class NotificationEvent
    PROTOCOL_MAJOR = 1

    attr_reader :message, :user, :activity_types

    def self.deliver_for(message:, user:, activity_types:)
      return unless BadgeState.enabled?

      new(message: message, user: user, activity_types: activity_types).deliver
    end

    def self.event_id_for(message:, user:)
      parts = []
      parts << ApplicationRecord.current_tenant if Sabha.saas? && ApplicationRecord.current_tenant.present?
      parts << message.id
      parts << user.id
      parts.join(":")
    end

    def initialize(message:, user:, activity_types:)
      @message = message
      @user = user
      @activity_types = Array(activity_types).map(&:to_sym).uniq.sort
    end

    def event_id
      self.class.event_id_for(message: message, user: user)
    end

    def deliver
      DesktopChannel.broadcast_to_user(user, as_json)
    end

    def as_json
      payload = Room::MessagePusher.payload_for(room: message.room, message: message)

      {
        type: "notification",
        protocol_major: PROTOCOL_MAJOR,
        event_id: event_id,
        message_id: message.id,
        activity_types: activity_types.map(&:to_s),
        title: payload.fetch(:title),
        body: payload.fetch(:body),
        path: payload.fetch(:path),
        badge: BadgeState.count_for(user)
      }
    end
  end
end
