module Room::Pinning
  extend ActiveSupport::Concern

  included do
    # A room's single pinned message (the `pinned_message_id` column). The FK
    # nullifies on the message's deletion, and Message::Pinnable clears it on a
    # soft delete, so a pin never dangles.
    belongs_to :pinned_message, class_name: "Message", optional: true

    after_update_commit :broadcast_pin_change, if: :saved_change_to_pinned_message_id?
  end

  # Pinning is for standing chat rooms — not one-off DMs or the contextual
  # thread/post panels.
  def pinnable?
    !direct? && !sub_room?
  end

  private
    # One column change re-renders the strip and flips the ⋯ control on both the
    # newly pinned and previously pinned messages. Broadcast viewer-less over the
    # room stream; the staff-only affordances are gated in CSS via the `.staff`
    # body class, never Current.user.
    def broadcast_pin_change
      Turbo::StreamsChannel.broadcast_replace_to(
        self, :messages,
        target: ActionView::RecordIdentifier.dom_id(self, :pinned),
        partial: "rooms/pinned_strip", locals: { room: self }
      )

      Message.where(id: saved_change_to_pinned_message_id.compact).find_each do |message|
        Turbo::StreamsChannel.broadcast_replace_to(
          self, :messages,
          target: ActionView::RecordIdentifier.dom_id(message, :pinning),
          partial: "messages/actions/pin", locals: { message: message }
        )
      end
    end
end
