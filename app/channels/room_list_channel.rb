class RoomListChannel < ApplicationCable::Channel
  def subscribed
    stream_for Current.account
  end
end
