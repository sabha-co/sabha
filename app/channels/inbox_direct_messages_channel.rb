class InboxDirectMessagesChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user, :inbox_direct_messages
  end
end
