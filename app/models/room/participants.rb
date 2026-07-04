# Lists the distinct users who have posted in a room, in the order they first
# appeared — the participant avatars a forum post's or chat thread's card shows.
# Shared by Rooms::Thread and Rooms::Post: both answer "who's talking here?" the
# same way, over their own message stream.
module Room::Participants
  extend ActiveSupport::Concern

  class_methods do
    # Batches participant lookup across many rooms so a gallery or message list
    # renders every card without an N+1 — one grouped scan plus one user load,
    # regardless of how many rooms are passed.
    def preload_participant_creators(rooms, limit: 5)
      rooms = rooms.to_a.uniq
      return {} if rooms.empty?

      ordered_creator_ids_by_room = grouped_creator_ids_for(rooms, limit:)
      users_by_id = User.where(id: ordered_creator_ids_by_room.values.flatten.uniq)
                        .includes(:badge, avatar_attachment: { blob: :variant_records })
                        .index_by(&:id)

      ordered_creator_ids_by_room.transform_values do |creator_ids|
        creator_ids.filter_map { |creator_id| users_by_id[creator_id] }
      end
    end

    private
      def grouped_creator_ids_for(rooms, limit:)
        room_ids = rooms.map(&:id)
        first_message_times = Message.active.where(room_id: room_ids)
                                            .group(:room_id, :creator_id)
                                            .minimum(:created_at)

        first_message_times.sort_by { |(room_id, creator_id), first_message_at| [ room_id, first_message_at, creator_id ] }
                           .each_with_object(Hash.new { |hash, room_id| hash[room_id] = [] }) do |((room_id, creator_id), _first_message_at), grouped_ids|
          next if grouped_ids[room_id].size >= limit

          grouped_ids[room_id] << creator_id
        end
      end
  end

  # Returns users in chronological order (by their first message in this room).
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
end
