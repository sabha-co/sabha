# Fetches direct message rooms for the user's DM inbox.
# Returns a relation that can be paginated using the room-based pagination scopes.
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
        .direct_rooms
        .joins(:room)
        .merge(Room.active)
        .with_has_unread_notifications
        .includes(room: [
          { memberships: { user: { avatar_attachment: { blob: :variant_records } } } },
          { last_message: [ :rich_text_body, { creator: { avatar_attachment: { blob: :variant_records } } } ] }
        ])
        .order("rooms.last_active_at DESC, rooms.id DESC")
        .extending(RoomPagination)
  end

  # Pagination scopes for memberships ordered by room.last_active_at, room.id
  # Uses composite conditions to handle ties in last_active_at
  module RoomPagination
    PAGE_SIZE = 10

    def last_page(page_size = PAGE_SIZE)
      limit(page_size)
    end

    def page_before(room, page_size = PAGE_SIZE)
      where(
        "(rooms.last_active_at > ?) OR (rooms.last_active_at = ? AND rooms.id > ?)",
        room.last_active_at, room.last_active_at, room.id
      ).last(page_size)
    end

    def page_after(room, page_size = PAGE_SIZE)
      where(
        "(rooms.last_active_at < ?) OR (rooms.last_active_at = ? AND rooms.id < ?)",
        room.last_active_at, room.last_active_at, room.id
      ).limit(page_size)
    end
  end
end
