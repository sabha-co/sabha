module Message::Unreadable
  extend ActiveSupport::Concern

  included do
    # Order matters: deliver_to_room advances the sender's read cursor, and
    # increment_unread_notifications_counters then bumps the counter for
    # memberships whose cursor sits before this message. Swap them and a
    # caught-up DM sender would bump their own badge.
    after_create_commit :deliver_to_room
    after_create_commit :increment_unread_notifications_counters
    after_update_commit :rebalance_unread_counters_if_deactivated
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
    # @everyone. Members watching live are skipped — they see the message as it
    # lands, and senders almost always fall in this bucket.
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
                .merge(Membership.with_message_unseen(created_at, id))
                .update_all("unread_notifications_count = unread_notifications_count + 1")
    end

    def rebalance_unread_counters_if_deactivated
      return unless saved_change_to_attribute?(:active) && !active?
      rebalance_unread_counters
    end

    def destroy_notifications_if_deactivated
      return unless saved_change_to_attribute?(:active) && !active?

      Notification.delete_all_and_broadcast(Notification.where(message_id: id))
    end

    # When a soft-deleted message is reactivated (a console/admin path),
    # restore the counter bumps that rebalance_unread_counters took away.
    # Only DM and @everyone messages are restored — named mentions need their
    # Notification rows back to count, and we don't recreate those on
    # reactivation.
    def restore_unread_notifications_counters_if_reactivated
      return unless saved_change_to_attribute?(:active) && active?
      return if event?
      return unless room.direct? || mentions_everyone?

      recipient_ids = room.direct? ? room.user_ids : room.user_ids - [ creator_id ]
      return if recipient_ids.empty?

      Membership.where(room_id: room_id, user_id: recipient_ids)
                .merge(Membership.with_message_unseen(created_at, id))
                .update_all("unread_notifications_count = unread_notifications_count + 1")
    end

    # Keeps memberships.unread_notifications_count consistent when this
    # message disappears from the room (soft- or hard-deleted). Called by
    # Message#destroy_all_associated_records as well as the deactivation
    # callback above.
    #
    # Only the DM counter needs rebalancing here: DMs count every unseen
    # message, so each membership whose cursor sat before this one loses a
    # count. Mention counters unwind through the notification destroy
    # (Notification.decrement_membership_counters), and derived unread itself
    # self-heals — the cursor comparison only sees active messages, so no
    # anchor needs advancing.
    def rebalance_unread_counters
      return unless room.direct?

      Membership.where(room_id: room_id)
                .merge(Membership.with_message_unseen(created_at, id))
                .update_all("unread_notifications_count = CASE WHEN unread_notifications_count > 0 THEN unread_notifications_count - 1 ELSE 0 END")
    end
end
