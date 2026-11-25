class BroadcastMentioneeSidebarUpdatesJob < ApplicationJob
  include ActionView::RecordIdentifier
  include DomHelper

  queue_as :default

  discard_on ActiveJob::DeserializationError::RecordNotFound

  def perform(message_id:)
    message = Message.find_by(id: message_id)
    return unless message
    return unless message.channel.sidebar_channel?

    affected_memberships(message).each do |membership|
      list_name = membership.sidebar_list_name
      Turbo::StreamsChannel.broadcast_replace_to(
        membership.user, :channels,
        target: dom_id(membership.channel, dom_prefix(list_name, :list_node_link)),
        partial: "users/sidebars/channels/shared_link",
        locals: { list_name:, membership: }
      )
    end
  end

  private
    def affected_memberships(message)
      scope = if message.mentions_everyone?
        message.channel.memberships
      else
        message.channel.memberships.where(user_id: message.mentionee_ids)
      end

      scope.visible
           .where.not(user_id: message.creator_id)
           .includes(:user)
    end
end
