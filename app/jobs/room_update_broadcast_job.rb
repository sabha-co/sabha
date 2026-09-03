class RoomUpdateBroadcastJob < ApplicationJob
  queue_as :default

  # The room was destroyed before this ran — nothing left to broadcast. Drop
  # only that case; a transient deserialization failure should still retry.
  discard_on ActiveJob::DeserializationError::RecordNotFound

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  def perform(room)
    return unless room.active?
    return unless room.sidebar_room?

    # Throttle updates to once every 5 seconds per room to avoid a thundering herd problem.
    lock_key = "room_update_broadcast_job_lock:#{room.id}"
    return unless Kredis.redis.set(lock_key, "1", nx: true, ex: 5)

    room.memberships.visible.includes(:user).find_each do |membership|
      broadcast_membership_update(membership, room)
    end
  end

  private

  def broadcast_membership_update(membership, room)
    list_name = membership.sidebar_list_name
    Turbo::StreamsChannel.broadcast_replace_to(
      membership.user, :rooms,
      target: [ room, "#{list_name}_list_node" ],
      partial: "users/sidebars/rooms/shared",
      locals: { membership: membership, list_name: list_name, room: room }
    )
  end
end
