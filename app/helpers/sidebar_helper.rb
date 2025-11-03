module SidebarHelper
  def inbox_sort_order
    sort_by_last_updated_newest_first
  end

  def all_rooms_sort_order
    sort_by_last_updated_newest_first
  end

  def sort_by_last_updated_newest_first
    raw "data-sorted-list-attribute-value='updatedAt' data-sorted-list-order-value='desc'"
  end

  def sidebar_membership_cache_key(prefix, membership)
    [ prefix, membership.room, membership.involvement, membership.unread?, membership.has_unread_notifications? ]
  end
end
