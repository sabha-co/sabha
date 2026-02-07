class UnreadMentionsNotifierJob < ApplicationJob
  def perform
    if Sabha.saas?
      # SaaS mode: iterate over all workspaces
      ApplicationRecord.with_each_tenant do
        notify_users_in_current_workspace
      end
    else
      # Single-tenant mode: run directly
      notify_users_in_current_workspace
    end

    log "Done notifying all users."
  end

  private

  def notify_users_in_current_workspace
    log_tenant_info if Sabha.saas?

    # Single consolidated query for all unread mentions
    unread_by_user = fetch_unread_mentions_by_user

    User.active.subscribed("notifications")
        .where(id: unread_by_user.keys)
        .find_each do |user|
      notify_user(user, unread_by_user[user.id])
    end
  end

  def log_tenant_info
    tenant = ApplicationRecord.current_tenant
    log "Processing workspace #{tenant}"
  end

  def fetch_unread_mentions_by_user
    cutoff_time = 7.days.ago
    notify_threshold = 12.hours.ago

    # Build a query that fetches all unread notifications across all users
    # This replaces the N+1 pattern of iterating users and then querying their mentions
    #
    # For non-direct rooms: messages where user is mentioned OR mentions_everyone is true
    # For direct rooms: all messages are notifications
    notifications_with_context = Message.active
      .joins(:room)
      .joins(<<~SQL.squish)
        INNER JOIN memberships
          ON memberships.room_id = messages.room_id
          AND memberships.active = 1
      SQL
      .joins(<<~SQL.squish)
        LEFT JOIN mentions
          ON mentions.message_id = messages.id
          AND mentions.user_id = memberships.user_id
      SQL
      .where("messages.created_at >= ?", cutoff_time)
      .where("messages.created_at >= COALESCE(memberships.notified_until, rooms.created_at)")
      .where("messages.created_at >= memberships.unread_at")
      .where.not("memberships.involvement = ?", "invisible")
      .where("memberships.unread_at IS NOT NULL")
      .where(<<~SQL.squish)
        (rooms.type = 'Rooms::Direct')
        OR (mentions.user_id IS NOT NULL)
        OR (messages.mentions_everyone = 1)
      SQL
      .select("messages.*, memberships.user_id AS notified_user_id")
      .includes(:creator, room: :users)
      .distinct

    # Group messages by user, filter to those with notifications older than 12 hours
    notifications_with_context
      .group_by(&:notified_user_id)
      .select { |_user_id, messages| messages.any? { |m| m.created_at <= notify_threshold } }
  end

  def notify_user(user, messages)
    return if messages.blank?

    messages.sort_by!(&:created_at)

    log "Found #{messages.count} mentions to notify about.", user

    NotifierMailer.unread_mentions(user, messages).deliver_now
    user.memberships.update_all(notified_until: Time.current)

    log "Notified about #{messages.count} unread mentions.", user
  rescue => e
    log "Failed to notify: #{e.message}", user
  end

  def log(message, user = nil)
    Rails.logger.info "[UnreadMentionsNotifierJob]#{user ? "[#{user.id}]" : ""} #{message}"
  end
end
