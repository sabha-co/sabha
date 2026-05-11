class Notification::Digest::Content
  ACTIVE_ROOM_MIN_MESSAGES = 3
  EXCERPT_LIMIT            = 5
  LOOKBACK                 = 1.week

  def initialize(user)
    @user = user
  end

  def empty?
    everyone_mentions.empty? && active_rooms.empty? && excerpts.empty?
  end

  def everyone_mentions
    @everyone_mentions ||= room_ids.empty? ? [] : Message
      .active
      .includes(:creator, :room, :rich_text_body)
      .where(room_id: room_ids, mentions_everyone: true)
      .where("messages.created_at > ?", LOOKBACK.ago)
      .order(created_at: :desc)
      .limit(EXCERPT_LIMIT)
      .to_a
  end

  def active_rooms
    @active_rooms ||= qualifying_room_ids
      .map { |id| [ rooms_by_id[id], counts_by_room_id[id] ] }
      .reject { |room, _| room.nil? }
      .sort_by { |_, count| -count }
  end

  def excerpts
    @excerpts ||= qualifying_room_ids.empty? ? [] : Message
      .active
      .includes(:creator, :room, :rich_text_body)
      .where(room_id: qualifying_room_ids)
      .where("messages.created_at > ?", LOOKBACK.ago)
      .order(created_at: :desc)
      .limit(EXCERPT_LIMIT)
      .to_a
  end

  private
    attr_reader :user

    def room_ids
      @room_ids ||= user
        .memberships
        .without_direct_rooms
        .without_thread_rooms
        .where.not(involvement: %w[ invisible nothing ])
        .joins(:room)
        .where(rooms: { active: true })
        .pluck("rooms.id")
    end

    def counts_by_room_id
      @counts_by_room_id ||= Message
        .active
        .where(room_id: room_ids)
        .where("messages.created_at > ?", LOOKBACK.ago)
        .group(:room_id)
        .count
    end

    def qualifying_room_ids
      @qualifying_room_ids ||= counts_by_room_id.select { |_, count| count >= ACTIVE_ROOM_MIN_MESSAGES }.keys
    end

    def rooms_by_id
      @rooms_by_id ||= Room.where(id: qualifying_room_ids).index_by(&:id)
    end
end
