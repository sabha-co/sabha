class BroadcastMentioneeSidebarUpdatesJob < ApplicationJob
  include ActionView::RecordIdentifier
  include DomHelper

  queue_as :default

  rescue_from ActiveJob::DeserializationError do
  end

  def perform(message_id:)
    message = Message.find_by(id: message_id)
    return unless message
    return unless message.room.sidebar_room?

    affected_memberships(message).each do |membership|
      list_name = membership.sidebar_list_name
      Turbo::StreamsChannel.broadcast_replace_to(
        membership.user, :rooms,
        target: dom_id(membership.room, dom_prefix(list_name, :list_node_link)),
        partial: "users/sidebars/rooms/shared_link",
        locals: { list_name:, membership: }
      )
    end
  end

  private
    def affected_memberships(message)
      scope = if message.mentions_everyone?
        message.room.memberships
      else
        message.room.memberships.where(user_id: message.mentionee_ids)
      end

      scope.visible
           .where.not(user_id: message.creator_id)
           .includes(:user)
    end
end
