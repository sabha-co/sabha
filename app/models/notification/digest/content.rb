class Notification::Digest::Content
  ACTIVE_CHANNEL_MIN_MESSAGES = 3
  EXCERPT_LIMIT            = 5
  LOOKBACK                 = 1.week

  def initialize(user)
    @user = user
  end

  def empty?
    everyone_mentions.empty? && active_channels.empty? && excerpts.empty?
  end

  def everyone_mentions
    @everyone_mentions ||= channel_ids.empty? ? [] : Message
      .active
      .includes(:creator, :channel, :rich_text_body)
      .where(channel_id: channel_ids, mentions_everyone: true)
      .where("messages.created_at > ?", LOOKBACK.ago)
      .order(created_at: :desc)
      .limit(EXCERPT_LIMIT)
      .to_a
  end

  def active_channels
    @active_channels ||= qualifying_channel_ids
      .map { |id| [ channels_by_id[id], counts_by_channel_id[id] ] }
      .reject { |channel, _| channel.nil? }
      .sort_by { |_, count| -count }
  end

  def excerpts
    @excerpts ||= qualifying_channel_ids.empty? ? [] : Message
      .active
      .includes(:creator, :channel, :rich_text_body)
      .where(channel_id: qualifying_channel_ids)
      .where("messages.created_at > ?", LOOKBACK.ago)
      .order(created_at: :desc)
      .limit(EXCERPT_LIMIT)
      .to_a
  end

  private
    attr_reader :user

    def channel_ids
      @channel_ids ||= user
        .memberships
        .without_direct_channels
        .without_thread_channels
        .where.not(involvement: %w[ invisible nothing ])
        .joins(:channel)
        .where(channels: { active: true })
        .pluck("channels.id")
    end

    def counts_by_channel_id
      @counts_by_channel_id ||= Message
        .active
        .where(channel_id: channel_ids)
        .where("messages.created_at > ?", LOOKBACK.ago)
        .group(:channel_id)
        .count
    end

    def qualifying_channel_ids
      @qualifying_channel_ids ||= counts_by_channel_id.select { |_, count| count >= ACTIVE_CHANNEL_MIN_MESSAGES }.keys
    end

    def channels_by_id
      @channels_by_id ||= Channel.where(id: qualifying_channel_ids).index_by(&:id)
    end
end
