# Per-channel eligibility predicates. The same predicates run at dispatch time
# and at delivery time, so state changes flow through one gate.
#
# v1 implementation note: receives_missed_email_for? and receives_digest? return
# false until U2 (User::NotificationSettings) and U3 (Account flags) supply the
# data. The seam is structural in U1 — no call sites yet (U4 wires it in).
#
# See docs/plans/NOTIFICATIONS-ARCHITECTURE.md § 4.
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

  def receives_missed_email_for?(_message, _activity_type)
    false
  end

  def receives_digest?
    false
  end

  private
    def common_gates_pass?(message)
      return false if user_id == message.creator_id
      return false unless active?
      return false if involved_in_invisible?
      return false unless message.active? && room.active?
      return false unless user.active? && user.verified? && !user.bot?
      return false unless user.can_ping?(message.creator)
      true
    end
end
