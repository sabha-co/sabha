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
      message: [
        :room,
        :rich_text_body,
        :mentions,
        :threads,
        { creator: [ :badge, { avatar_attachment: { blob: :variant_records } } ] },
        { boosts: { booster: { avatar_attachment: { blob: :variant_records } } } },
        { attachment_attachment: { blob: :variant_records } }
      ],
      actor: [ :badge, { avatar_attachment: { blob: :variant_records } } ]
    )
  }

  validates :activity_type, inclusion: { in: %w[mention boost thread_reply] }

  # Deletes the given scope of notifications and broadcasts removal to each user's activity stream.
  # Loads records first, then deletes by ID to avoid double-querying the same WHERE clause.
  def self.delete_all_and_broadcast(scope)
    notifications = scope.includes(:user).to_a
    return if notifications.empty?

    where(id: notifications.map(&:id)).delete_all

    notifications.each do |notification|
      Turbo::StreamsChannel.broadcast_remove_to(
        [ notification.user, :inbox_activity ],
        target: ActionView::RecordIdentifier.dom_id(notification)
      )
    end

    # Boost groups use a stable DOM ID separate from individual notification IDs
    notifications.select(&:boost_notification?).group_by { |n| [ n.user_id, n.message_id ] }.each do |(_, message_id), group|
      Turbo::StreamsChannel.broadcast_remove_to(
        [ group.first.user, :inbox_activity ],
        target: Notification::BoostGroup.dom_id_for(message_id)
      )
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
