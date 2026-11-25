# Lists the distinct users who have posted in a channel, in the order they first
# appeared — the participant avatars a forum post's or chat thread's card shows.
# Shared by Channels::Thread and Channels::Post: both answer "who's talking here?" the
# same way, over their own message stream.
module Channel::Participants
  extend ActiveSupport::Concern

  class_methods do
    # Batches participant lookup across many channels so a gallery or message list
    # renders every card without an N+1 — one grouped scan plus one user load,
    # regardless of how many channels are passed.
    def preload_participant_creators(channels, limit: 5)
      channels = channels.to_a.uniq
      return {} if channels.empty?

      ordered_creator_ids_by_channel = grouped_creator_ids_for(channels, limit:)
      users_by_id = User.where(id: ordered_creator_ids_by_channel.values.flatten.uniq)
                        .includes(:badge, avatar_attachment: { blob: :variant_records })
                        .index_by(&:id)

      ordered_creator_ids_by_channel.transform_values do |creator_ids|
        creator_ids.filter_map { |creator_id| users_by_id[creator_id] }
      end
    end

    private
      def grouped_creator_ids_for(channels, limit:)
        channel_ids = channels.map(&:id)
        first_message_times = Message.active.where(channel_id: channel_ids)
                                            .group(:channel_id, :creator_id)
                                            .minimum(:created_at)

        first_message_times.sort_by { |(channel_id, creator_id), first_message_at| [ channel_id, first_message_at, creator_id ] }
                           .each_with_object(Hash.new { |hash, channel_id| hash[channel_id] = [] }) do |((channel_id, creator_id), _first_message_at), grouped_ids|
          next if grouped_ids[channel_id].size >= limit

          grouped_ids[channel_id] << creator_id
        end
      end
  end

  # Returns users in chronological order (by their first message in this channel).
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
