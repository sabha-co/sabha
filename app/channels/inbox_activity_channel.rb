class InboxActivityChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user, :inbox_activity
  end
end
