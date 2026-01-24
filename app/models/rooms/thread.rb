# Rooms that start off from a parent message and inherit permissions from that message's room.
class Rooms::Thread < Room
  validates_presence_of :parent_message

  # Returns users in chronological order (by their first message in the thread)
  def participant_creators(limit: 5)
    ordered_creator_ids = messages.active
      .group(:creator_id)
      .order("MIN(created_at)")
      .limit(limit)
      .pluck(:creator_id)

    return [] if ordered_creator_ids.empty?

    users_by_id = User.where(id: ordered_creator_ids)
      .includes(:badge, avatar_attachment: { blob: :variant_records })
      .index_by(&:id)

    ordered_creator_ids.filter_map { |id| users_by_id[id] }
  end

  def default_involvement(user: nil)
    if user.present? && (user == creator || user == parent_message&.creator)
      "everything"
    else
      "invisible"
    end
  end

  # Deactivates the thread. Called either when:
  # 1. An admin deletes this thread directly from the UI
  # 2. The parent room is deactivated (cascades to all its threads)
  # Note: Deleting the parent message does NOT deactivate the thread.
  def deactivate
    transaction do
      Membership.where(room_id: id).update_all(active: false)
      Message.unscoped.where(room_id: id).update_all(active: false)
      deactivate!
    end
  end

  # Thread handles its own reactivation
  def reactivate
    transaction do
      Membership.where(room_id: id, active: false).update_all(active: true)
      Message.unscoped.where(room_id: id, active: false).update_all(active: true)
      activate!
    end
  end
end
