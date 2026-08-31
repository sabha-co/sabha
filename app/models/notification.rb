class Notification < ApplicationRecord
  include Pagination

  belongs_to :user
  belongs_to :message
  belongs_to :actor, class_name: "User"
  belongs_to :boost, optional: true

  scope :ordered, -> { order(:created_at) }
  scope :with_message_and_creator, -> {
    includes(
      :boost,
      :user,
      message: [
        { room: :parent_room },
        :rich_text_body,
        :threads,
        { creator: [ :badge, { avatar_attachment: { blob: :variant_records } } ] },
        { boosts: { booster: { avatar_attachment: { blob: :variant_records } } } },
        { attachment_attachment: { blob: :variant_records } }
      ],
      actor: [ :badge, { avatar_attachment: { blob: :variant_records } } ]
    )
  }

  validates :activity_type, inclusion: { in: %w[mention boost thread_reply] }

  # Appends each notification in the scope to its user's activity stream and
  # refreshes their activity indicator — the append mirror of #delete_all_and_broadcast.
  def self.append_and_broadcast(scope)
    scope.with_message_and_creator.each do |notification|
      Turbo::StreamsChannel.broadcast_append_to(
        [ notification.user, :inbox_activity ],
        target: "inbox",
        partial: "notifications/notification",
        locals: { notification: notification, timestamp_style: :long_datetime }
      )
      notification.user.broadcast_activity_indicator
    end
  end

  # Deletes the given scope of notifications and broadcasts removal to each user's activity stream.
  # Loads records first, then deletes by ID to avoid double-querying the same WHERE clause.
  def self.delete_all_and_broadcast(scope)
    notifications = scope.includes(:user, :message).to_a
    return if notifications.empty?

    decrement_membership_counters(notifications)
    where(id: notifications.map(&:id)).delete_all

    notifications.each do |notification|
      Turbo::StreamsChannel.broadcast_remove_to(
        [ notification.user, :inbox_activity ],
        target: ActionView::RecordIdentifier.dom_id(notification)
      )
    end

    notifications.map(&:user).uniq.each(&:broadcast_activity_indicator)

    # Boost groups use a stable DOM ID separate from individual notification IDs
    notifications.select(&:boost_notification?).group_by { |n| [ n.user_id, n.message_id ] }.each do |(_, message_id), group|
      Turbo::StreamsChannel.broadcast_remove_to(
        [ group.first.user, :inbox_activity ],
        target: Notification::BoostGroup.dom_id_for(message_id)
      )
    end
  end

  # Decrement the unread_notifications_count for memberships whose users had
  # mention notifications removed and where the message still falls within
  # their unread window. Clamps at 0 to avoid drift below zero.
  def self.decrement_membership_counters(notifications)
    notifications.select(&:mention?).each do |notification|
      message = notification.message
      next unless message

      Membership.where(room_id: message.room_id, user_id: notification.user_id)
                .merge(Membership.with_message_unseen(message.created_at, message.id))
                .update_all("unread_notifications_count = CASE WHEN unread_notifications_count > 0 THEN unread_notifications_count - 1 ELSE 0 END")
    end
  end

  def mention?
    activity_type == "mention"
  end

  def boost_notification?
    activity_type == "boost"
  end

  def thread_reply?
    activity_type == "thread_reply"
  end
end
