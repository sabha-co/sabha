module Message::Pinnable
  extend ActiveSupport::Concern

  included do
    after_update_commit :unpin_when_removed, if: :saved_change_to_active?
  end

  def pinned?
    room.pinned_message_id == id
  end

  # Pin this message in its room, replacing whatever was pinned — one pin per
  # room. Setting the same message again is a no-op (no column change, no
  # broadcast).
  def pin!
    room.update!(pinned_message: self)
  end

  def unpin!
    room.update!(pinned_message: nil) if pinned?
  end

  private
    # Deleting a message is a soft delete; if it was the room's pinned message,
    # drop the pin (and clear the strip) so it can't outlive what it points at.
    def unpin_when_removed
      unpin! if deactivated?
    end
end
