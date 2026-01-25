class Room::PushMessageJob < ApplicationJob
  def perform(room, message)
    return if DemoMode.enabled?

    Room::MessagePusher.new(room:, message:).push
  end
end
