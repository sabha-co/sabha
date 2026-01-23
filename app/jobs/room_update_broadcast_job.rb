class RoomUpdateBroadcastJob < ApplicationJob
  queue_as :default

  SIDEBAR_SECTIONS = [ :starred_rooms, :shared_rooms ].freeze

  rescue_from ActiveJob::DeserializationError do
  end

  retry_on ActiveRecord::Deadlocked, wait: :exponentially, attempts: 3

  def perform(room)
    return unless room.active?

    # Throttle updates to once every 5 seconds per room to avoid a thundering herd problem.
    lock_key = "room_update_broadcast_job_lock:#{room.id}"
    return unless Kredis.redis.set(lock_key, "1", nx: true, ex: 5)

    room.memberships.visible.find_each do |membership|
      broadcast_membership_update(membership, room)
    end
  end

  private

  def broadcast_membership_update(membership, room)
    SIDEBAR_SECTIONS.each do |list_name|
      html = render_partial_for(membership, list_name, room)
      Turbo::StreamsChannel.broadcast_replace_to(
        membership.user, :rooms,
        target: [ room, helpers.dom_prefix(list_name, :list_node) ],
        html: html
      )
    end
  end

  def render_partial_for(membership, list_name, room)
    ApplicationController.render(
      partial: "users/sidebars/rooms/shared",
      locals: { membership: membership, list_name: list_name, room: room }
    )
  end

  def helpers
    ApplicationController.helpers
  end
end
