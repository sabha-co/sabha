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
      .includes(:room)
      .with_room_by_last_active_newest_first
      .limit(10)
  end

  # Starred room memberships shown in the "Favorites" section.
  #
  def starred
    shared_base.starred
  end

  # Unstarred shared rooms with unseen messages — the v2.1 UNREAD section.
  # Starred wins over unread (a starred room stays in Favorites), forums keep
  # their post-derived dots in FORUMS, so no room is listed twice.
  def unread
    shared_base.unstarred.without_forum_rooms.unread
  end

  # Unstarred, caught-up shared room memberships shown in the "Rooms" section.
  # Forums are listed separately.
  #
  def shared
    shared_base.unstarred.without_forum_rooms.read
  end

  # Forum memberships shown in the "Forums" section.
  #
  def forums
    shared_base.unstarred.forum_rooms
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

  # Presence for the DM rows — the roster's connected signal, one query.
  # Returns a hash of user_id => :active | :away | :offline.
  def direct_member_statuses(direct_room_members)
    user_ids = direct_room_members.values.flatten.map(&:id).uniq
    return {} if user_ids.empty?

    Membership.activity_statuses_for(user_ids)
  end

  private

  def shared_base
    user.memberships
      .visible
      .without_thread_rooms
      .without_direct_rooms
      .active_rooms
      .includes(:room)
  end

  def other_members(memberships)
    memberships.map(&:user).reject { |u| u.id == user.id }
  end
end
