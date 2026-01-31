class BroadcastInboxDirectMessagesJob < ApplicationJob
  queue_as :default

  def perform(room_id:)
    room = Room.includes(last_message: [ :rich_text_body, { creator: { avatar_attachment: { blob: :variant_records } } } ])
               .find_by(id: room_id)
    return unless room&.direct?

    room.memberships.active.visible.each do |membership|
      user = membership.user
      direct_room_members = { room.id => room.members_for_display(excluding: user) }

      Turbo::StreamsChannel.broadcast_remove_to(
        user, :inbox_direct_messages,
        target: ActionView::RecordIdentifier.dom_id(room, :dm_inbox)
      )

      Turbo::StreamsChannel.broadcast_prepend_to(
        user, :inbox_direct_messages,
        target: "inbox",
        partial: "inboxes/direct_messages/conversation",
        locals: {
          membership: membership,
          direct_room_members: direct_room_members
        }
      )
    end
  end
end
