class BroadcastMentioneeSidebarUpdatesJob < ApplicationJob
  queue_as :default

  rescue_from ActiveJob::DeserializationError do
  end

  def perform(message_id:)
    message = Message.find_by(id: message_id)
    return unless message

    message.mentionees.each do |user|
      memberships = user.memberships.shared.visible
        .with_has_unread_notifications
        .with_room_by_last_active_newest_first
        .to_a

      starred, unstarred = memberships.partition(&:starred?)

      { starred_rooms: starred, shared_rooms: unstarred }.each do |list_name, list|
        Turbo::StreamsChannel.broadcast_replace_to(
          user, :rooms,
          target: list_name,
          partial: "users/sidebars/rooms/shared_rooms_list",
          locals: { list_name: list_name, memberships: list },
          attributes: { maintain_scroll: true }
        )
      end
    end
  end
end
