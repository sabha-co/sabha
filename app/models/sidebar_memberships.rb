# Query object for fetching sidebar memberships.
#
# Encapsulates the complex queries needed for the sidebar, keeping
# the controller concern clean. Handles both direct messages and
# shared channels with proper eager loading to avoid N+1 queries.
#
class SidebarMemberships
  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Direct message memberships shown in the horizontal scroll area.
  # Only includes DMs that are:
  # - Visible (not set to invisible involvement)
  # - In active channels
  # - Recently active (unread OR channel updated in last 7 days)
  #
  # Sorted by most recent activity first, limited to 10.
  #
  def direct
    user.memberships
      .visible
      .direct_channels
      .active_channels
      .recently_active_or_unread
      .includes(:channel)
      .with_channel_by_last_active_newest_first
      .limit(10)
  end

  # Starred channel memberships shown in the "Favorites" section.
  #
  def starred
    shared_base.starred
  end

  # Unstarred shared channel memberships shown in the "All Channels" section.
  #
  def shared
    shared_base.unstarred
  end

  # Hidden channel memberships (channels with invisible involvement).
  # Shown in a collapsible "Hidden Channels" section so users can find and unhide them.
  #
  def hidden
    user.memberships
      .where(involvement: :invisible)
      .without_thread_channels
      .without_direct_channels
      .active_channels
      .includes(:channel)
  end

  # Preloads users for each direct channel to display avatars without N+1 queries.
  # Returns a hash of channel_id => [users], excluding the current user.
  # Falls back to showing current user if they're the only member.
  #
  def direct_channel_members(memberships)
    return {} if memberships.empty?

    Membership
      .where(channel_id: memberships.map(&:channel_id), active: true)
      .includes(user: { avatar_attachment: { blob: :variant_records } })
      .group_by(&:channel_id)
      .transform_values { |ms| other_members(ms).presence || [ user ] }
  end

  private

  def shared_base
    user.memberships
      .visible
      .without_thread_channels
      .without_direct_channels
      .active_channels
      .includes(:channel)
  end

  def other_members(memberships)
    memberships.map(&:user).reject { |u| u.id == user.id }
  end
end
