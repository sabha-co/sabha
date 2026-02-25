class Room::PushMessageJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  def perform(room, message)
    return if DemoMode.enabled?

    Room::MessagePusher.new(room:, message:).push
  end
end
