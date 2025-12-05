module Sidebar
  extend ActiveSupport::Concern

  included do
    helper_method :for_each_sidebar_section
  end

  def set_sidebar_memberships
    memberships = Current.user.memberships.visible.without_thread_rooms.joins(:room).where(rooms: { active: true }).with_has_unread_notifications.includes(:room).with_room_by_last_active_newest_first

    # Get all direct memberships and filter them
    all_direct_memberships = memberships.select { |m| m.room.direct? }
    @direct_memberships   = filter_direct_memberships(all_direct_memberships)

    # Preload users with avatars for direct rooms to avoid N+1 queries
    # Build a hash of room_id => [users excluding current user] for the view to use
    @direct_room_members = {}
    if @direct_memberships.any?
      room_ids = @direct_memberships.map { |m| m.room.id }

      # Load all memberships for these rooms in one query, with users and avatars preloaded
      memberships_for_rooms = Membership.where(room_id: room_ids, active: true)
        .includes(user: { avatar_attachment: { blob: :variant_records } })

      # Group by room_id and exclude current user
      memberships_for_rooms.group_by(&:room_id).each do |room_id, memberships|
        users = memberships.map(&:user).reject { |u| u.id == Current.user.id }
        @direct_room_members[room_id] = users
      end

      # Ensure each room has at least the current user if no other members
      @direct_memberships.each do |m|
        @direct_room_members[m.room.id] ||= []
        @direct_room_members[m.room.id] = [ Current.user ] if @direct_room_members[m.room.id].empty?
      end
    end

    # Get other memberships using the without_direct_rooms scope
    other_memberships     = Current.user.memberships.visible.without_thread_rooms.without_direct_rooms.joins(:room).where(rooms: { active: true }).with_has_unread_notifications.includes(:room)
    @all_memberships      = other_memberships
    @starred_memberships  = other_memberships

    @direct_memberships.select! { |m| m.room.messages_count > 0 }
  end

  def for_each_sidebar_section
    [ :starred_rooms, :shared_rooms ].each do |name|
      yield name
    end
  end

  private

  def filter_direct_memberships(direct_memberships)
    # Filter direct memberships to only include:
    # 1. Memberships with unread messages
    # 2. Memberships updated in the last 7 days
    direct_memberships.select do |membership|
      membership.unread? ||
        membership.has_unread_notifications? ||
        (membership.room.updated_at.present? && membership.room.updated_at >= 7.days.ago)
    end.sort_by { |m| m.room.updated_at || Time.at(0) }.reverse
  end
end
