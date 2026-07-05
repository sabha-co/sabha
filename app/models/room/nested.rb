# Cascade-deactivation lifecycle shared by nested sub-rooms — Rooms::Thread (a
# chat thread) and Rooms::Post (a forum post). Both soft-delete along with their
# memberships and messages, and `cascade_deactivated` records whether the delete
# cascaded from the parent (a room deactivating its threads, a forum its posts)
# as opposed to an individual delete. Only cascade-deactivated sub-rooms are
# restored when the parent reactivates, so one deleted on its own stays deleted
# across a parent delete/restore (R15).
module Room::Nested
  extend ActiveSupport::Concern

  # Deactivates the sub-room. Called either when an admin deletes it directly, or
  # when its parent is deactivated (which cascades). `cascade: true` marks the
  # latter — see the R15 note above.
  def deactivate(cascade: false)
    transaction do
      Membership.where(room_id: id).update_all(active: false)
      Message.where(room_id: id).update_all(active: false)
      destroy_notifications_for_messages
      self.cascade_deactivated = cascade
      deactivate!
    end
  end

  def reactivate
    transaction do
      Membership.where(room_id: id, active: false).update_all(active: true)
      Message.where(room_id: id, active: false).update_all(active: true)
      self.cascade_deactivated = false
      activate!
    end
  end
end
