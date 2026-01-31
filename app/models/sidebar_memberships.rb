# Query object for fetching sidebar memberships.
#
# Encapsulates the complex queries needed for the sidebar, keeping
# the controller concern clean. Handles both direct messages and
# shared rooms with proper eager loading to avoid N+1 queries.
#
class SidebarMemberships
  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Direct message memberships shown in the horizontal scroll area.
  # Only includes DMs that are:
  # - Visible (not set to invisible involvement)
  # - In active rooms
  # - Recently active (unread OR room updated in last 7 days)
  #
  # Sorted by most recent activity first, limited to 10.
  #
  def direct
    user.memberships
      .visible
      .direct_rooms
      .active_rooms
      .recently_active_or_unread
      .with_has_unread_notifications
      .includes(:room)
      .with_room_by_last_active_newest_first
      .limit(10)
  end

  # Shared room memberships (Open/Closed rooms) shown in My Rooms and All Rooms.
  # Visibility between sections is controlled client-side by Stimulus based on involvement.
  #
  def shared
    user.memberships
      .visible
      .without_thread_rooms
      .without_direct_rooms
      .active_rooms
      .with_has_unread_notifications
      .includes(:room)
  end

  # Hidden room memberships (rooms with invisible involvement).
  # Shown in a collapsible "Hidden Rooms" section so users can find and unhide them.
  #
  def hidden
    user.memberships
      .where(involvement: :invisible)
      .without_thread_rooms
      .without_direct_rooms
      .active_rooms
      .includes(:room)
  end

  # Preloads users for each direct room to display avatars without N+1 queries.
  # Returns a hash of room_id => [users], excluding the current user.
  # Falls back to showing current user if they're the only member.
  #
  def direct_room_members(memberships)
    return {} if memberships.empty?

    Membership
      .where(room_id: memberships.map(&:room_id), active: true)
      .includes(user: { avatar_attachment: { blob: :variant_records } })
      .group_by(&:room_id)
      .transform_values { |ms| other_members(ms).presence || [ user ] }
  end

  private

  def other_members(memberships)
    memberships.map(&:user).reject { |u| u.id == user.id }
  end
end
