# Rooms that start off from a parent message and inherit permissions from that message's room.
class Rooms::Thread < Room
  class NestedThreadError < StandardError; end

  validates_presence_of :parent_message

  class << self
    def preload_participant_creators(threads, limit: 5)
      threads = threads.to_a.uniq
      return {} if threads.empty?

      ordered_creator_ids_by_thread = grouped_creator_ids_for(threads, limit:)
      users_by_id = User.where(id: ordered_creator_ids_by_thread.values.flatten.uniq)
                        .includes(:badge, avatar_attachment: { blob: :variant_records })
                        .index_by(&:id)

      ordered_creator_ids_by_thread.transform_values do |creator_ids|
        creator_ids.filter_map { |creator_id| users_by_id[creator_id] }
      end
    end

    private
      def grouped_creator_ids_for(threads, limit:)
        thread_ids = threads.map(&:id)
        first_message_times = Message.active.where(room_id: thread_ids)
                                            .group(:room_id, :creator_id)
                                            .minimum(:created_at)

        first_message_times.sort_by { |(thread_id, creator_id), first_message_at| [ thread_id, first_message_at, creator_id ] }
                           .each_with_object(Hash.new { |hash, thread_id| hash[thread_id] = [] }) do |((thread_id, creator_id), _first_message_at), grouped_ids|
          next if grouped_ids[thread_id].size >= limit

          grouped_ids[thread_id] << creator_id
        end
      end
  end

  def self.find_or_create_for(parent_message, users:)
    raise NestedThreadError if parent_message.room.thread?

    parent_message.threads.active.find_by(type: "Rooms::Thread") ||
      create_for({ parent_message_id: parent_message.id }, users: users)
  end

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

  def applicable_activity_types(message)
    types = [ :thread_reply ]
    return types if parent_room&.direct?
    types << :mention if message.mentionees.any?
    types
  end

  # Deactivates the thread. Called either when:
  # 1. An admin deletes this thread directly from the UI
  # 2. The parent room is deactivated (cascades to all its threads)
  # Note: Deleting the parent message does NOT deactivate the thread.
  def deactivate
    transaction do
      Membership.where(room_id: id).update_all(active: false)
      Message.where(room_id: id).update_all(active: false)
      deactivate!
    end
  end

  # Thread handles its own reactivation
  def reactivate
    transaction do
      Membership.where(room_id: id, active: false).update_all(active: true)
      Message.where(room_id: id, active: false).update_all(active: true)
      activate!
    end
  end
end
