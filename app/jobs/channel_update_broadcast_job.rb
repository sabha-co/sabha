class ChannelUpdateBroadcastJob < ApplicationJob
  queue_as :default

  # The channel was destroyed before this ran — nothing left to broadcast. Drop
  # only that case; a transient deserialization failure should still retry.
  discard_on ActiveJob::DeserializationError::RecordNotFound

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  def perform(channel)
    return unless channel.active?
    return unless channel.sidebar_channel?

    # Throttle updates to once every 5 seconds per channel to avoid a thundering herd problem.
    lock_key = "channel_update_broadcast_job_lock:#{channel.id}"
    return unless Kredis.redis.set(lock_key, "1", nx: true, ex: 5)

    channel.memberships.visible.includes(:user).find_each do |membership|
      broadcast_membership_update(membership, channel)
    end
  end

  private

  def broadcast_membership_update(membership, channel)
    list_name = membership.sidebar_list_name
    Turbo::StreamsChannel.broadcast_replace_to(
      membership.user, :channels,
      target: [ channel, "#{list_name}_list_node" ],
      partial: "users/sidebars/channels/shared",
      locals: { membership: membership, list_name: list_name, channel: channel }
    )
  end
end
