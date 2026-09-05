module SidebarHelper
  SORTED_LIST_NEWEST_FIRST = {
    "data-sorted-list-attribute-value" => "updatedAt",
    "data-sorted-list-order-value" => "desc"
  }.freeze

  DM_SEPARATOR_THRESHOLD = 5

  def can_create_dms?
    Current.user.can_create_direct_messages?
  end

  def show_dm_section?(direct_memberships)
    can_create_dms? || direct_memberships.any?
  end

  def show_dm_separator?(direct_memberships)
    show_dm_section?(direct_memberships) && direct_memberships.size <= DM_SEPARATOR_THRESHOLD
  end

  def inbox_sort_order
    tag.attributes(SORTED_LIST_NEWEST_FIRST)
  end

  def all_rooms_sort_order
    tag.attributes(SORTED_LIST_NEWEST_FIRST)
  end

  def sidebar_membership_cache_key(prefix, membership, membership_unread = membership.unread?)
    [ prefix, membership.room, membership.involvement, membership.starred?, membership.involved_in_nothing?, membership_unread, membership.has_unread_notifications? ]
  end
end
