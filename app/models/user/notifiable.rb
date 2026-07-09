module User::Notifiable
  extend ActiveSupport::Concern

  included do
    has_many :notifications
    has_many :notification_bundles, class_name: "Notification::Bundle", dependent: :destroy
    has_one :notification_settings, class_name: "User::NotificationSettings", dependent: :destroy

    scope :weekly_digest_eligible, -> {
      verified
        .where(status: statuses[:active])
        .where.not(role: roles[:bot])
        .joins(:notification_settings)
        .includes(:notification_settings)
        .where(user_notification_settings: { weekly_digest_subscribed: true })
        .merge(User::NotificationSettings.due_for_weekly_digest)
    }

    after_create_commit :ensure_notification_settings
    after_update_commit :broadcast_activity_indicator, if: :saved_change_to_activity_seen_at?
  end

  # Returns the user's open accumulator for missed-notification email candidates,
  # opening one if none is active. Race-safe via the partial unique index — a
  # concurrent open by a parallel writer raises RecordNotUnique on the loser
  # and falls through to a second read.
  def active_notification_bundle
    notification_bundles.active.first || open_notification_bundle!
  end

  # Public so batch dispatch can open bundles for users not in a pre-fetched
  # active set without re-running `active.first` for each miss.
  def open_notification_bundle!
    frequency = notification_settings&.email_frequency || "hourly"
    starts_at = Time.current
    notification_bundles.create!(
      frequency: frequency,
      starts_at: starts_at,
      ends_at:   starts_at + Notification::Bundle::FREQUENCY_WINDOWS.fetch(frequency)
    )
  rescue ActiveRecord::RecordNotUnique
    notification_bundles.active.first!
  end

  def unsubscribe_from_email!(surface)
    (notification_settings || create_notification_settings!).unsubscribe_from!(surface)
  end

  # Builds this user's weekly digest content and mails it if non-empty.
  # `last_digest_sent_at` only advances on actual delivery so quiet weeks
  # don't dedup-lock subsequent runs.
  def deliver_weekly_digest_now
    content = Notification::Digest::Content.new(self)
    return if content.empty?

    WeeklyDigestMailer.digest(self, content).deliver_now
    notification_settings.update!(last_digest_sent_at: Time.current)
  end

  # Persists the watermark used by unseen_activity? to gate the sidebar dot.
  # Monotonic: only advances forward so stale `loaded_at` values from background
  # tabs can't reopen the dot. Broadcast is fired by after_update_commit below.
  def touch_activity_seen_at(time = Time.current)
    return if time.nil?
    return if activity_seen_at.present? && activity_seen_at >= time

    update!(activity_seen_at: time)
  end

  # True when at least one notification row has arrived since the user last
  # opened the Activity tab. Drives the sidebar Activity dot.
  def unseen_activity?
    scope = notifications
    scope = scope.where("notifications.created_at > ?", activity_seen_at) if activity_seen_at
    scope.exists?
  end

  # Marks all direct message rooms as read up to the loaded timestamp.
  def mark_direct_messages_as_read(loaded_at)
    dms_until = freshness_checked_time(loaded_at)

    memberships.unread.direct_rooms.each do |m|
      m.read_until(dms_until)
    end
  end

  # Marks inbox as read up to the timestamps when messages were last loaded.
  # Uses stale detection: if timestamp is > 1 hour old, uses current time instead
  # (user likely left the page open without interacting).
  #
  # For activity: DMs are always marked as read. For other rooms, only marks as read
  # if the room had no non-notified messages in the window (avoids accidentally marking
  # unread messages as read when user only viewed activity)
  def mark_inbox_as_read(messages_loaded_at:, notifications_loaded_at:, activity_loaded_at:)
    messages_until = freshness_checked_time(messages_loaded_at)
    notifications_until = freshness_checked_time(notifications_loaded_at)
    activity_until = freshness_checked_time(activity_loaded_at)

    memberships.unread.each { |m| m.read_until(messages_until) }
    memberships.notifications_on.unread.each { |m| m.read_until(notifications_until) }
    mark_notified_rooms_as_read(activity_until, include_dms: true)

    touch_activity_seen_at(activity_until)
  end

  def broadcast_activity_indicator
    Turbo::StreamsChannel.broadcast_replace_to(
      self, :sidebar_activity_indicator,
      target: "sidebar_activity_indicator",
      partial: "users/sidebars/activity_indicator",
      locals: { user: self }
    )
  end

  private
    def ensure_notification_settings
      create_notification_settings! unless notification_settings
    end

    # Marks rooms as read where all unread messages have corresponding notifications.
    # For non-DM rooms, only marks as read if there are no non-notified messages in the window.
    def mark_notified_rooms_as_read(until_time, include_dms: false)
      notified_room_ids = notifications
        .where("notifications.created_at <= ?", until_time)
        .joins(:message).distinct.pluck(Arel.sql("messages.room_id"))

      memberships.unread.includes(:room).where(room_id: notified_room_ids).each do |m|
        if m.room.is_a?(Rooms::Direct)
          m.read_until(until_time) if include_dms
          next
        end
        next if m.last_read_at.nil?

        unseen_window = m.room.messages.without_events
          .after_cursor(m.last_read_at, m.last_read_message_id)
          .created_before(until_time)

        notified_message_ids = Notification.where(user: self)
          .where(message_id: unseen_window.select(:id))
          .pluck(:message_id)

        non_notified = unseen_window.where.not(id: notified_message_ids)

        if non_notified.none?
          m.read_until(until_time)
        else
          m.clear_unread_notifications_until(until_time)
        end
      end
    end

    # Returns Time.current if the timestamp is missing or stale (> 1 hour old).
    # Stale timestamps indicate the user left the inbox page open without interacting.
    def freshness_checked_time(iso8601_time)
      return Time.current unless iso8601_time.present?

      time = Time.iso8601(iso8601_time)
      time > 1.hour.ago ? time : Time.current
    end
end
