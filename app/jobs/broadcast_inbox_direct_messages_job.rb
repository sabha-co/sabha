class BroadcastInboxDirectMessagesJob < ApplicationJob
  queue_as :default

  def perform(channel_id:)
    channel = Channel.includes(last_message: [ :rich_text_body, { creator: { avatar_attachment: { blob: :variant_records } } } ])
               .find_by(id: channel_id)
    return unless channel&.direct?

    channel.memberships.active.visible.each do |membership|
      user = membership.user
      direct_channel_members = { channel.id => channel.members_for_display(excluding: user) }

      Turbo::StreamsChannel.broadcast_remove_to(
        user, :inbox_direct_messages,
        target: ActionView::RecordIdentifier.dom_id(channel, :dm_inbox)
      )

      Turbo::StreamsChannel.broadcast_prepend_to(
        user, :inbox_direct_messages,
        target: "inbox",
        partial: "inboxes/direct_messages/conversation",
        locals: {
          membership: membership,
          direct_channel_members: direct_channel_members
        }
      )
    end
  end
end
