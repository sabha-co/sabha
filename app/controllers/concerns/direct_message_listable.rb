# Assembles the DM conversation list shared by the inbox and the split-view
# rail on direct-room pages: memberships ordered by activity, each room's
# display members, and presence for the 1:1 conversations.
module DirectMessageListable
  private
    def load_dm_conversations(open_room: nil)
      @memberships = Inbox::DirectMessagesQuery.new(Current.user).call.last_page
      @pinned_dm_membership = pinned_dm_membership(open_room, @memberships)

      room_ids = @memberships.map(&:room_id)
      room_ids << @pinned_dm_membership.room_id if @pinned_dm_membership

      @direct_room_members = Rooms::Direct.members_for_display_by_room(room_ids, excluding: Current.user)
      @direct_member_statuses = direct_member_statuses(@direct_room_members)
    end

    # The open conversation is pinned above the rail when it's dropped off the
    # first page — a reader with many DMs opening an older one — so the rail
    # always shows the conversation being viewed. It stays out of @memberships so
    # the paginated list keeps its activity order and cursor intact.
    def pinned_dm_membership(open_room, memberships)
      return unless open_room&.direct?
      return if memberships.any? { |membership| membership.room_id == open_room.id }

      Current.user.memberships.visible.find_by(room_id: open_room.id)
    end

    def direct_member_statuses(direct_room_members)
      Membership.activity_statuses_for(
        direct_room_members.values.select(&:one?).map { |members| members.first.id }
      )
    end
end
