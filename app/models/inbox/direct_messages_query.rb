# Fetches direct message channels for the user's DM inbox.
# Returns a relation that can be paginated using the channel-based pagination scopes.
class Inbox::DirectMessagesQuery
  def initialize(user)
    @user = user
  end

  def call
    base_query
  end

  private

  attr_reader :user

  def base_query
    user.memberships
        .visible
        .direct_channels
        .joins(:channel)
        .merge(Channel.active)
        .includes(channel: [
          { memberships: { user: { avatar_attachment: { blob: :variant_records } } } },
          { last_message: [ :rich_text_body, { creator: { avatar_attachment: { blob: :variant_records } } } ] }
        ])
        .order("channels.last_active_at DESC, channels.id DESC")
        .extending(ChannelPagination)
  end

  # Pagination scopes for memberships ordered by channel.last_active_at, channel.id
  # Uses composite conditions to handle ties in last_active_at
  module ChannelPagination
    PAGE_SIZE = 10

    def last_page(page_size = PAGE_SIZE)
      limit(page_size)
    end

    def page_before(channel, page_size = PAGE_SIZE)
      where(
        "(channels.last_active_at > ?) OR (channels.last_active_at = ? AND channels.id > ?)",
        channel.last_active_at, channel.last_active_at, channel.id
      ).last(page_size)
    end

    def page_after(channel, page_size = PAGE_SIZE)
      where(
        "(channels.last_active_at < ?) OR (channels.last_active_at = ? AND channels.id < ?)",
        channel.last_active_at, channel.last_active_at, channel.id
      ).limit(page_size)
    end
  end
end
