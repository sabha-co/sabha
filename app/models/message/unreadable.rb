module Message::Unreadable
  extend ActiveSupport::Concern

  included do
    # Order matters: deliver_to_room sets unread_at for disconnected read
    # memberships, and increment_unread_notifications_counters then bumps the
    # counter for memberships with unread_at <= created_at. Swap them and the
    # counter never bumps for a read → unread transition.
    after_create_commit :deliver_to_room
    after_create_commit :increment_unread_notifications_counters
    after_update_commit :clear_unread_timestamps_if_deactivated
    after_update_commit :destroy_notifications_if_deactivated
    after_update_commit :restore_unread_notifications_counters_if_reactivated
  end

  private
    def deliver_to_room
      room.receive(self)
    end

    # Bumps unread_notifications_count for memberships affected by this message.
    # Mirrors the with_has_unread_notifications semantics: DM rooms count every
    # unread message (including the sender's, matching the old scope which made
    # no creator distinction in DMs); other rooms only count mentions and
    # @everyone. Connected users (unread_at IS NULL) are skipped — they see
    # the message live, and senders almost always fall in this bucket.
    def increment_unread_notifications_counters
      return if event?

      recipient_ids = if room.direct?
        room.user_ids
      elsif mentions_everyone?
        room.user_ids - [ creator_id ]
      else
        mentionee_ids - [ creator_id ]
      end

      return if recipient_ids.empty?

      Membership.where(room_id: room_id, user_id: recipient_ids)
                .where("unread_at IS NOT NULL AND unread_at <= ?", created_at)
                .update_all("unread_notifications_count = unread_notifications_count + 1")
    end

    def clear_unread_timestamps_if_deactivated
      return unless saved_change_to_attribute?(:active) && !active?
      rebalance_unread_counters
    end

    def destroy_notifications_if_deactivated
      return unless saved_change_to_attribute?(:active) && !active?

      Notification.delete_all_and_broadcast(Notification.where(message_id: id))
    end

    # When a soft-deleted message is reactivated (a console/admin path),
    # restore the counter bumps that clear_unread_timestamps_if_deactivated
    # took away. Only DM and @everyone messages are restored — named mentions
    # need their Notification rows back to count under either the old scope
    # or the new column, and we don't recreate those on reactivation.
    def restore_unread_notifications_counters_if_reactivated
      return unless saved_change_to_attribute?(:active) && active?
      return if event?
      return unless room.direct? || mentions_everyone?

      recipient_ids = room.direct? ? room.user_ids : room.user_ids - [ creator_id ]
      return if recipient_ids.empty?

      Membership.where(room_id: room_id, user_id: recipient_ids)
                .where("unread_at IS NOT NULL AND unread_at <= ?", created_at)
                .update_all("unread_notifications_count = unread_notifications_count + 1")
    end

    # Keeps memberships.unread_notifications_count and unread_at consistent
    # when this message disappears from the room (soft- or hard-deleted).
    # Called by Message#destroy_all_associated_records as well as the
    # deactivation callback above.
    #
    # Two effects per call:
    #   1. DMs only: every membership whose unread window contained this
    #      message loses one from its count (using < to leave the anchor
    #      membership for the second pass below).
    #   2. Any membership anchored exactly at this message's timestamp gets
    #      its anchor advanced to the next active message (or marked read),
    #      with its counter recomputed from the new anchor.
    def rebalance_unread_counters
      if room.direct?
        Membership.where(room_id: room_id)
                  .where("unread_at IS NOT NULL AND unread_at < ?", created_at)
                  .update_all("unread_notifications_count = MAX(unread_notifications_count - 1, 0)")
      end

      room.memberships.where(unread_at: created_at).find_each do |membership|
        next_unread = room.messages.active.ordered
                         .where("created_at > ?", created_at)
                         .first

        if next_unread
          membership.update!(
            unread_at: next_unread.created_at,
            unread_notifications_count: membership.count_unread_notifications_from(next_unread.created_at)
          )
        else
          membership.read
        end
      end
    end
end
