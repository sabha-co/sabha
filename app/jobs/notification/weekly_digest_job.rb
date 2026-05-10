class Notification::WeeklyDigestJob < ApplicationJob
  ACTIVE_ROOM_MIN_MESSAGES = 3
  EXCERPT_LIMIT            = 5
  DIGEST_DEDUP_WINDOW      = 6.days
  DIGEST_LOOKBACK          = 1.week

  def perform
    return if DemoMode.enabled?

    Notification::Bundle.gc_terminal!

    return unless Account.sole&.weekly_digest_enabled?

    eligible_users.find_each do |user|
      content = build_content_for(user)
      # Skip without stamping last_digest_sent_at — quiet-week members get
      # re-evaluated next run instead of being dedup-locked.
      next if content.values.all?(&:empty?)

      WeeklyDigestMailer.digest(user, content).deliver_now
      user.notification_settings.update!(last_digest_sent_at: Time.current)
    end
  end

  private
    def eligible_users
      User
        .joins(:notification_settings)
        .where(user_notification_settings: { weekly_digest_subscribed: true })
        .where.not(role: User.roles[:bot])
        .where(status: User.statuses[:active])
        .where.not(verified_at: nil)
        .where(
          "user_notification_settings.last_digest_sent_at IS NULL OR " \
          "user_notification_settings.last_digest_sent_at < ?",
          DIGEST_DEDUP_WINDOW.ago
        )
    end

    def build_content_for(user)
      memberships = user
        .memberships
        .without_direct_rooms
        .without_thread_rooms
        .where.not(involvement: %w[ invisible nothing ])
        .joins(:room)
        .where(rooms: { active: true })

      room_ids = memberships.pluck("rooms.id")
      return empty_content if room_ids.empty?

      everyone_mentions = Message
        .active
        .where(room_id: room_ids, mentions_everyone: true)
        .where("messages.created_at > ?", DIGEST_LOOKBACK.ago)
        .order(created_at: :desc)
        .limit(EXCERPT_LIMIT)
        .to_a

      messages_since = Message
        .active
        .where(room_id: room_ids)
        .where("messages.created_at > ?", DIGEST_LOOKBACK.ago)

      counts_by_room_id = messages_since.group(:room_id).count
      qualifying_room_ids = counts_by_room_id.select { |_, count| count >= ACTIVE_ROOM_MIN_MESSAGES }.keys
      rooms_by_id = Room.where(id: qualifying_room_ids).index_by(&:id)
      active_rooms = qualifying_room_ids
        .map { |id| [ rooms_by_id[id], counts_by_room_id[id] ] }
        .reject { |room, _| room.nil? }
        .sort_by { |_, count| -count }

      excerpts = qualifying_room_ids.empty? ? [] : Message
        .active
        .where(room_id: qualifying_room_ids)
        .where("messages.created_at > ?", DIGEST_LOOKBACK.ago)
        .order(created_at: :desc)
        .limit(EXCERPT_LIMIT)
        .to_a

      {
        everyone_mentions: everyone_mentions,
        active_rooms:      active_rooms,
        excerpts:          excerpts
      }
    end

    def empty_content
      { everyone_mentions: [], active_rooms: [], excerpts: [] }
    end
end
