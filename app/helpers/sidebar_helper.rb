module SidebarHelper
  SORTED_LIST_NEWEST_FIRST = {
    "data-sorted-list-attribute-value" => "updatedAt",
    "data-sorted-list-order-value" => "desc"
  }.freeze

  def inbox_sort_order
    tag.attributes(SORTED_LIST_NEWEST_FIRST)
  end

  def all_rooms_sort_order
    tag.attributes(SORTED_LIST_NEWEST_FIRST)
  end

  def sidebar_membership_cache_key(prefix, membership)
    [ prefix, membership.room, membership.involvement, membership.unread?, membership.has_unread_notifications? ]
  end
end
