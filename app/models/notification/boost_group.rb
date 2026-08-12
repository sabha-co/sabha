class Notification::BoostGroup
  attr_reader :notifications

  delegate :message, :created_at, :user, to: :latest_notification

  def self.dom_id_for(message_id)
    "boost_group_message_#{message_id}"
  end

  def initialize(notifications)
    @notifications = Array(notifications)
  end

  def boost_group?     = true
  def boost_notification? = true
  def mention?         = false
  def thread_reply?    = false

  def actors
    notifications.map(&:actor).uniq(&:id)
  end

  def boost_contents
    notifications.filter_map { |n| n.boost&.content }.uniq
  end

  def latest_notification
    notifications.last
  end

  def group_dom_id
    self.class.dom_id_for(message.id)
  end

  # For dom_id compatibility (used by individual notification broadcasts)
  def to_key
    [ latest_notification.id ]
  end

  def model_name
    Notification.model_name
  end

  def to_partial_path
    "notifications/boost_group"
  end

  # Broadcasts a group update after a single boost notification is removed.
  # Replaces the group element if boosts remain, removes it entirely if none do.
  def self.broadcast_update_after_removal(user:, message_id:)
    remaining = Notification.where(
      user_id: user.id, message_id: message_id, activity_type: "boost"
    ).with_message_and_creator.ordered.to_a

    target = dom_id_for(message_id)

    if remaining.any?
      Turbo::StreamsChannel.broadcast_replace_to(
        [ user, :inbox_activity ],
        target: target,
        partial: "notifications/boost_group",
        locals: { notification: new(remaining) }
      )
    else
      Turbo::StreamsChannel.broadcast_remove_to(
        [ user, :inbox_activity ],
        target: target
      )
    end
  end
end
