# Per-channel notification eligibility predicates. The same predicates run at
# dispatch time and at delivery time, so state changes (block, deactivation,
# settings flip) flow through one gate.
module Membership::Notifiable
  extend ActiveSupport::Concern

  def receives_in_app_row_for?(message, activity_type)
    activity_type = activity_type.to_sym
    return false unless Notification::Routing::IN_APP_ROW_TYPES.include?(activity_type)
    return false unless common_gates_pass?(message)

    case activity_type
    when :mention
      effective_involvement.in?(%i[mentions everything])
    when :thread_reply, :boost
      !involved_in_invisible?
    end
  end

  def receives_push_for?(message, activity_type)
    activity_type = activity_type.to_sym
    return false unless Notification::Routing::PUSH_TYPES.include?(activity_type)
    return false unless common_gates_pass?(message)
    return false if connected?
    # Settings-missing means "default" (push_enabled defaults to true), so only
    # suppress when an explicit false is on file. Mirrors how missed-email is
    # opt-in (settings-missing → false) by aligning the guard with the column
    # default rather than the present-or-absent state.
    return false if user.notification_settings && !user.notification_settings.push_enabled?

    case activity_type
    when :mention
      effective_involvement.in?(%i[mentions everything])
    when :direct_message
      true
    when :everyone_room_message
      effective_involvement == :everything
    when :thread_reply
      !involved_in_invisible?
    end
  end

  def receives_missed_email_for?(message, activity_type)
    activity_type = activity_type.to_sym
    return false unless Notification::Routing::EMAIL_TYPES.include?(activity_type)
    return false unless common_gates_pass?(message)
    return false unless account_email_notifications_enabled?
    return false unless user.notification_settings&.missed_email_enabled?
    return false unless user.workspace_locally_away?

    case activity_type
    when :mention
      effective_involvement.in?(%i[mentions everything])
    when :direct_message
      effective_involvement != :nothing
    end
  end

  private
    def common_gates_pass?(message)
      return false if user_id == message.creator_id
      return false unless active?
      return false if involved_in_invisible?
      return false unless message.active? && room.active?
      return false unless user.active? && user.verified? && !user.bot?
      # Set-based block check: Message memoizes the (blocker_id, blocked_id)
      # pairs touching its creator so per-recipient predicate calls don't each
      # fire two block queries (the N+N hot path for large-room dispatch).
      # Semantically equivalent to !user.can_ping?(message.creator).
      return false if message.blocked_user_ids_with_creator.include?(user_id)
      true
    end

    def account_email_notifications_enabled?
      # Belt-and-braces gate: if the operator removes the provider key after
      # toggling the account flag on, dispatch stops trying to deliver instead
      # of trusting a stale `true` value in the DB.
      Sabha.email_configured? && Account.sole.email_notifications_enabled?
    end
end
