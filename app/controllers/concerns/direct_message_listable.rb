# Assembles the DM conversation list shared by the inbox and the split-view
# rail on direct-room pages: memberships ordered by activity, each room's
# display members, and presence for the 1:1 conversations.
module DirectMessageListable
  private
    def load_dm_conversations
      @memberships = Inbox::DirectMessagesQuery.new(Current.user).call.last_page
      @direct_room_members = Rooms::Direct.members_for_display_by_room(
        @memberships.map(&:room_id), excluding: Current.user
      )
      @direct_member_statuses = direct_member_statuses(@direct_room_members)
    end

    def direct_member_statuses(direct_room_members)
      Membership.activity_statuses_for(
        direct_room_members.values.select(&:one?).map { |members| members.first.id }
      )
    end
end
